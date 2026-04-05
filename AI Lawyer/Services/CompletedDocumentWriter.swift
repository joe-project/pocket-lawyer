import Foundation
import PDFKit
import UIKit

final class CompletedDocumentWriter {
    func makeCompletedPDF(
        originalData: Data,
        processed: ProcessedDocument,
        draft: DocumentAutofillDraft
    ) throws -> URL {
        switch processed.originalFileType {
        case .pdf:
            if processed.kind == .fillablePDF {
                return try fillPDF(originalData: originalData, draft: draft)
            }
            return try overlayOrAppendPDF(originalData: originalData, draft: draft)
        case .image:
            return try renderImageAsCompletedPDF(originalData: originalData, draft: draft)
        default:
            return try overlayOrAppendPDF(originalData: originalData, draft: draft)
        }
    }

    func completedFileName(for originalName: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let base = URL(fileURLWithPath: originalName).deletingPathExtension().lastPathComponent
        return "\(base)_completed_\(formatter.string(from: date)).pdf"
    }

    func summaryText(for draft: DocumentAutofillDraft) -> String {
        var lines = [draft.summary, ""]
        for field in draft.fields {
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let printable = value.isEmpty ? "[Missing]" : value
            lines.append("\(field.label): \(printable)")
        }
        return lines.joined(separator: "\n")
    }

    func previewImage(for pdfURL: URL) -> UIImage? {
        guard let document = PDFDocument(url: pdfURL),
              let page = document.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: bounds.size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
    }

    private func fillPDF(originalData: Data, draft: DocumentAutofillDraft) throws -> URL {
        guard let document = PDFDocument(data: originalData) else {
            throw NSError(domain: "CompletedDocumentWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: "The PDF could not be filled."])
        }

        let lookup = Dictionary(uniqueKeysWithValues: draft.fields.map { ($0.fieldName.lowercased(), $0) })

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.widgetFieldType != nil {
                let rawName = (annotation.fieldName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let key = rawName.lowercased()
                let direct = lookup[key]
                let fuzzy = draft.fields.first {
                    $0.label.caseInsensitiveCompare(rawName) == .orderedSame ||
                    $0.fieldName.caseInsensitiveCompare(rawName.replacingOccurrences(of: " ", with: "_")) == .orderedSame
                }
                if let field = direct ?? fuzzy {
                    annotation.widgetStringValue = field.value
                }
            }
        }

        guard let data = document.dataRepresentation() else {
            throw NSError(domain: "CompletedDocumentWriter", code: 2, userInfo: [NSLocalizedDescriptionKey: "The completed PDF could not be generated."])
        }
        return try writeTempPDF(data)
    }

    private func overlayOrAppendPDF(originalData: Data, draft: DocumentAutofillDraft) throws -> URL {
        guard let document = PDFDocument(data: originalData) else {
            throw NSError(domain: "CompletedDocumentWriter", code: 3, userInfo: [NSLocalizedDescriptionKey: "The PDF could not be prepared."])
        }

        let pageRect = firstPageRect(in: document)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { context in
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                context.beginPage()
                drawPDFPage(page, in: context.cgContext, rect: pageRect)
                drawOverlayFields(
                    draft.fields.filter { $0.pageIndex == pageIndex && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                    on: context.cgContext,
                    pageRect: pageRect
                )
            }

            context.beginPage()
            drawDraftSummaryPage(draft, in: context.cgContext, rect: pageRect)
        }

        return try writeTempPDF(data)
    }

    private func renderImageAsCompletedPDF(originalData: Data, draft: DocumentAutofillDraft) throws -> URL {
        guard let image = UIImage(data: originalData) else {
            throw NSError(domain: "CompletedDocumentWriter", code: 4, userInfo: [NSLocalizedDescriptionKey: "The image could not be prepared."])
        }

        let rect = CGRect(origin: .zero, size: image.size == .zero ? CGSize(width: 612, height: 792) : image.size)
        let renderer = UIGraphicsPDFRenderer(bounds: rect)
        let data = renderer.pdfData { context in
            context.beginPage()
            image.draw(in: rect)
            drawOverlayFields(
                draft.fields.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                on: context.cgContext,
                pageRect: rect
            )

            context.beginPage()
            drawDraftSummaryPage(draft, in: context.cgContext, rect: rect)
        }

        return try writeTempPDF(data)
    }

    private func drawPDFPage(_ page: PDFPage, in context: CGContext, rect: CGRect) {
        UIColor.white.setFill()
        context.fill(rect)
        context.saveGState()
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1, y: -1)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()
    }

    private func drawOverlayFields(_ fields: [AutofillDraftField], on context: CGContext, pageRect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ]

        var fallbackY: CGFloat = 44
        for field in fields {
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            let rect: CGRect
            if let pdfBounds = field.pdfBounds {
                rect = CGRect(x: pdfBounds.maxX + 6, y: pageRect.height - pdfBounds.maxY - 4, width: min(180, pageRect.width - pdfBounds.maxX - 12), height: 40)
            } else if let normalized = field.normalizedBounds {
                let converted = CGRect(
                    x: normalized.minX * pageRect.width + 6,
                    y: (1 - normalized.maxY) * pageRect.height,
                    width: min(pageRect.width * 0.4, 190),
                    height: 40
                )
                rect = converted
            } else {
                rect = CGRect(x: pageRect.width * 0.55, y: fallbackY, width: pageRect.width * 0.35, height: 40)
                fallbackY += 46
            }

            let background = UIBezierPath(roundedRect: rect.insetBy(dx: -4, dy: -2), cornerRadius: 6)
            UIColor.white.withAlphaComponent(0.88).setFill()
            background.fill()

            NSString(string: field.label).draw(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 12), withAttributes: labelAttributes)
            NSString(string: value).draw(in: CGRect(x: rect.minX, y: rect.minY + 12, width: rect.width, height: rect.height - 12), withAttributes: valueAttributes)
        }
    }

    private func drawDraftSummaryPage(_ draft: DocumentAutofillDraft, in context: CGContext, rect: CGRect) {
        UIColor.white.setFill()
        context.fill(rect)

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: UIColor.black
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black
        ]

        let margin: CGFloat = 36
        NSString(string: "Pocket Lawyer Autofill Draft").draw(in: CGRect(x: margin, y: margin, width: rect.width - margin * 2, height: 24), withAttributes: titleAttributes)
        NSString(string: draft.summary).draw(in: CGRect(x: margin, y: margin + 28, width: rect.width - margin * 2, height: 36), withAttributes: bodyAttributes)

        var y = margin + 80
        for field in draft.fields {
            let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let printable = value.isEmpty ? "[Missing]" : value
            let line = "\(field.label): \(printable)"
            NSString(string: line).draw(in: CGRect(x: margin, y: y, width: rect.width - margin * 2, height: 18), withAttributes: bodyAttributes)
            y += 20
            if y > rect.height - margin {
                break
            }
        }
    }

    private func firstPageRect(in document: PDFDocument) -> CGRect {
        if let page = document.page(at: 0) {
            let rect = page.bounds(for: .mediaBox)
            if rect.width > 0 && rect.height > 0 {
                return rect
            }
        }
        return CGRect(x: 0, y: 0, width: 612, height: 792)
    }

    private func writeTempPDF(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PocketLawyer_Completed_\(UUID().uuidString).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}
