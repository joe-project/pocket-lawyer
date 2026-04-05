import Foundation
import PDFKit
import Vision
import UIKit

final class DocumentProcessingService {
    private struct OCRLine {
        let text: String
        let normalizedBounds: CGRect
    }

    func processDocument(data: Data, fileName: String) async throws -> ProcessedDocument {
        let lower = fileName.lowercased()
        if lower.hasSuffix(".pdf") {
            return try await processPDF(data: data, fileName: fileName)
        }
        return try await processImage(data: data, fileName: fileName)
    }

    private func processPDF(data: Data, fileName: String) async throws -> ProcessedDocument {
        guard let pdf = PDFDocument(data: data) else {
            throw NSError(domain: "DocumentProcessingService", code: 1, userInfo: [NSLocalizedDescriptionKey: "The PDF could not be opened."])
        }

        var fields: [ParsedDocumentField] = []
        var textChunks: [String] = []
        var foundFillableField = false

        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex) else { continue }

            for annotation in page.annotations where annotation.widgetFieldType != nil {
                foundFillableField = true
                let label = annotation.fieldName?.trimmingCharacters(in: .whitespacesAndNewlines)
                fields.append(
                    ParsedDocumentField(
                        name: label?.isEmpty == false ? label! : "field_\(pageIndex)_\(fields.count + 1)",
                        label: label?.isEmpty == false ? label! : "Field \(fields.count + 1)",
                        pageIndex: pageIndex,
                        existingValue: annotation.widgetStringValue,
                        pdfBounds: annotation.bounds,
                        normalizedBounds: nil
                    )
                )
            }

            if let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !pageText.isEmpty {
                textChunks.append(pageText)
            }
        }

        var kind: ImportedDocumentKind = foundFillableField ? .fillablePDF : .flatPDF

        if !foundFillableField && textChunks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            kind = .scannedPDF
            let ocrResult = try await ocrPDF(pdf)
            textChunks = ocrResult.textChunks
            fields = deriveFields(from: ocrResult.linesByPage)
        } else if !foundFillableField {
            fields = deriveFields(fromExtractedText: textChunks.joined(separator: "\n"))
        }

        return ProcessedDocument(
            originalFileName: fileName,
            originalFileType: .pdf,
            kind: kind,
            title: stripExtension(from: fileName),
            pageCount: max(pdf.pageCount, 1),
            extractedText: textChunks.joined(separator: "\n\n"),
            fields: fields
        )
    }

    private func processImage(data: Data, fileName: String) async throws -> ProcessedDocument {
        guard let image = UIImage(data: data) else {
            throw NSError(domain: "DocumentProcessingService", code: 2, userInfo: [NSLocalizedDescriptionKey: "The image could not be opened."])
        }

        let lines = try await recognizeText(in: image)
        let extractedText = lines.map(\.text).joined(separator: "\n")
        let fields = deriveFields(from: [0: lines])

        return ProcessedDocument(
            originalFileName: fileName,
            originalFileType: .image,
            kind: .image,
            title: stripExtension(from: fileName),
            pageCount: 1,
            extractedText: extractedText,
            fields: fields
        )
    }

    private func ocrPDF(_ pdf: PDFDocument) async throws -> (textChunks: [String], linesByPage: [Int: [OCRLine]]) {
        var textChunks: [String] = []
        var linesByPage: [Int: [OCRLine]] = [:]

        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex),
                  let image = render(page: page) else { continue }
            let lines = try await recognizeText(in: image)
            linesByPage[pageIndex] = lines
            let text = lines.map(\.text).joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textChunks.append(text)
            }
        }

        return (textChunks, linesByPage)
    }

    private func recognizeText(in image: UIImage) async throws -> [OCRLine] {
        guard let cgImage = image.cgImage else {
            return []
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { observation -> OCRLine? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    return OCRLine(text: text, normalizedBounds: observation.boundingBox)
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func deriveFields(from linesByPage: [Int: [OCRLine]]) -> [ParsedDocumentField] {
        var fields: [ParsedDocumentField] = []
        let labelHints = [
            "name", "case number", "court", "address", "phone", "email",
            "plaintiff", "defendant", "petitioner", "respondent",
            "incident", "date", "signature"
        ]

        for (pageIndex, lines) in linesByPage.sorted(by: { $0.key < $1.key }) {
            for line in lines {
                let lower = line.text.lowercased()
                guard labelHints.contains(where: { lower.contains($0) }) else { continue }
                let cleaned = line.text.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                fields.append(
                    ParsedDocumentField(
                        name: cleaned.lowercased().replacingOccurrences(of: " ", with: "_"),
                        label: cleaned,
                        pageIndex: pageIndex,
                        existingValue: nil,
                        pdfBounds: nil,
                        normalizedBounds: line.normalizedBounds
                    )
                )
            }
        }

        return uniqueFields(fields)
    }

    private func deriveFields(fromExtractedText text: String) -> [ParsedDocumentField] {
        let candidates = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let hints = [
            "name", "case number", "court", "address", "phone", "email",
            "plaintiff", "defendant", "petitioner", "respondent",
            "incident", "date", "signature"
        ]

        let fields = candidates.compactMap { line -> ParsedDocumentField? in
            let lower = line.lowercased()
            guard hints.contains(where: { lower.contains($0) }) else { return nil }
            let cleaned = line.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedDocumentField(
                name: cleaned.lowercased().replacingOccurrences(of: " ", with: "_"),
                label: cleaned,
                pageIndex: 0,
                existingValue: nil,
                pdfBounds: nil,
                normalizedBounds: nil
            )
        }

        return uniqueFields(fields)
    }

    private func uniqueFields(_ fields: [ParsedDocumentField]) -> [ParsedDocumentField] {
        var seen = Set<String>()
        var result: [ParsedDocumentField] = []
        for field in fields {
            let key = field.label.lowercased()
            if seen.insert(key).inserted {
                result.append(field)
            }
        }
        return result
    }

    private func render(page: PDFPage) -> UIImage? {
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

    private func stripExtension(from fileName: String) -> String {
        URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }
}
