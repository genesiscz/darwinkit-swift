import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import Vision
@testable import DarwinKitCore

/// Real Vision OCR on a generated image whose only text sits in its top-right quadrant.
@Suite("Vision OCR Integration")
struct VisionOCRIntegrationTests {

    private static let text = "HELLO REGION"
    private static let imageWidth = 1600
    private static let imageHeight = 800

    /// Draws `text` in black on white, left edge at x = 920 px and baseline 200 px below the top edge, so it lies in
    /// the right half and the top half with margin from both centre lines.
    private func renderImage() throws -> URL {
        let width = Self.imageWidth
        let height = Self.imageHeight
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestImageError.context
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 64, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: Self.text, attributes: attributes))

        let left: CGFloat = 920
        let baselineFromTop: CGFloat = 200
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        // Precondition of every test below: the text really is inside the top-right quadrant, clear of the centre.
        guard left > CGFloat(width) / 2 + 50,
              left + lineWidth < CGFloat(width) - 50,
              baselineFromTop - ascent > 50,
              baselineFromTop + descent < CGFloat(height) / 2 - 50 else {
            throw TestImageError.layout(width: lineWidth, ascent: ascent, descent: descent)
        }

        // CGContext puts its origin at the bottom-left.
        context.textPosition = CGPoint(x: left, y: CGFloat(height) - baselineFromTop)
        CTLineDraw(line, context)

        guard let image = context.makeImage() else {
            throw TestImageError.context
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("darwinkit_ocr_region_\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw TestImageError.write
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestImageError.write
        }
        return url
    }

    private enum TestImageError: Error {
        case context
        case write
        case layout(width: CGFloat, ascent: CGFloat, descent: CGFloat)
    }

    private func ocr(_ url: URL, _ extra: [String: Any] = [:]) throws -> (text: String, bounds: [CGRect]) {
        var params: [String: AnyCodable] = ["path": AnyCodable(url.path)]
        for (key, value) in extra {
            params[key] = AnyCodable(value)
        }
        let handler = VisionHandler(provider: AppleVisionProvider())
        let response = try handler.handle(JsonRpcRequest(id: "e2e", method: "vision.ocr", params: params))
        let result = try #require(response as? [String: Any])
        let blocks = try #require(result["blocks"] as? [[String: Any]])
        let bounds = try blocks.map { block -> CGRect in
            let b = try #require(block["bounds"] as? [String: Any])
            return CGRect(
                x: try #require(b["x"] as? CGFloat),
                y: try #require(b["y"] as? CGFloat),
                width: try #require(b["width"] as? CGFloat),
                height: try #require(b["height"] as? CGFloat)
            )
        }
        return (try #require(result["text"] as? String), bounds)
    }

    private func describe(_ rects: [CGRect]) -> String {
        rects.map { String(format: "{x %.4f, y %.4f, w %.4f, h %.4f}", $0.origin.x, $0.origin.y, $0.width, $0.height) }
            .joined(separator: " ")
    }

    @Test("a whole-image read finds the text in the top-right quadrant")
    func wholeImage() throws {
        let url = try renderImage()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try ocr(url)
        print("[ocr-e2e] whole image: text=\(result.text.debugDescription) bounds=\(describe(result.bounds))")

        #expect(result.text.uppercased().contains("HELLO"))
        let box = try #require(result.bounds.first)
        #expect(box.origin.x > 0.5)
        #expect(box.origin.y > 0.5)  // bottom-left origin: the top half has y above 0.5
    }

    @Test("a region over the left half finds no text")
    func leftHalfFindsNothing() throws {
        let url = try renderImage()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try ocr(url, ["region": ["x": 0, "y": 0, "width": 0.5, "height": 1]])
        print("[ocr-e2e] left half: text=\(result.text.debugDescription) bounds=\(describe(result.bounds))")

        #expect(result.text.isEmpty)
        #expect(result.bounds.isEmpty)
    }

    @Test("a region over the right half finds the text with bounds in full-image coordinates")
    func rightHalfFullImageBounds() throws {
        let url = try renderImage()
        defer { try? FileManager.default.removeItem(at: url) }

        let whole = try ocr(url)
        let right = try ocr(url, ["region": ["x": 0.5, "y": 0, "width": 0.5, "height": 1]])
        print("[ocr-e2e] right half: text=\(right.text.debugDescription) bounds=\(describe(right.bounds))")

        #expect(right.text.uppercased().contains("HELLO"))
        let box = try #require(right.bounds.first)
        let wholeBox = try #require(whole.bounds.first)
        #expect(box.origin.x > 0.5)
        // The same words read through a region land where the whole-image read put them.
        #expect(abs(box.origin.x - wholeBox.origin.x) < 0.01)
        #expect(abs(box.origin.y - wholeBox.origin.y) < 0.01)
        #expect(abs(box.width - wholeBox.width) < 0.02)
        #expect(abs(box.height - wholeBox.height) < 0.02)
    }

    @Test("region y counts from the top: the top half finds the text, the bottom half does not")
    func regionOriginIsTopLeft() throws {
        let url = try renderImage()
        defer { try? FileManager.default.removeItem(at: url) }

        let top = try ocr(url, ["region": ["x": 0, "y": 0, "width": 1, "height": 0.5]])
        let bottom = try ocr(url, ["region": ["x": 0, "y": 0.5, "width": 1, "height": 0.5]])
        print("[ocr-e2e] top half: text=\(top.text.debugDescription) bounds=\(describe(top.bounds))")
        print("[ocr-e2e] bottom half: text=\(bottom.text.debugDescription) bounds=\(describe(bottom.bounds))")

        #expect(top.text.uppercased().contains("HELLO"))
        let box = try #require(top.bounds.first)
        #expect(box.origin.x > 0.5)
        #expect(box.origin.y > 0.5)
        #expect(bottom.text.isEmpty)
    }

    @Test("language_correction false still reads the text")
    func languageCorrectionOff() throws {
        let url = try renderImage()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try ocr(url, [
            "region": ["x": 0.5, "y": 0, "width": 0.5, "height": 0.5],
            "language_correction": false,
        ])
        print("[ocr-e2e] right top quadrant, no correction: text=\(result.text.debugDescription) bounds=\(describe(result.bounds))")

        #expect(result.text.uppercased().contains("HELLO"))
        let box = try #require(result.bounds.first)
        #expect(box.origin.x > 0.5)
        #expect(box.origin.y > 0.5)
    }

    /// The reason `AppleVisionProvider` maps boxes back: Vision itself reports them relative to the region of
    /// interest. If a later macOS changes that, this test fails before callers get boxes mapped twice.
    @Test("Vision reports boxes under a region of interest relative to that region")
    func visionBoxesAreRegionRelative() throws {
        let url = try renderImage()
        defer { try? FileManager.default.removeItem(at: url) }

        func rawBoxes(_ roi: CGRect?) throws -> [CGRect] {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            if let roi = roi {
                request.regionOfInterest = roi
            }
            try VNImageRequestHandler(url: url, options: [:]).perform([request])
            return (request.results ?? []).map(\.boundingBox)
        }

        let rightHalf = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let whole = try #require(try rawBoxes(nil).first)
        let raw = try #require(try rawBoxes(rightHalf).first)
        let mapped = OCRRegion.fullImageRect(raw, in: rightHalf)
        print("[ocr-e2e] raw Vision box, no region: \(describe([whole]))")
        print("[ocr-e2e] raw Vision box, right-half region: \(describe([raw])) -> mapped \(describe([mapped]))")

        // Text at about x 0.575 of the image is at about x 0.15 of the right half.
        #expect(raw.origin.x < 0.5)
        #expect(abs(raw.origin.x - (whole.origin.x - 0.5) / 0.5) < 0.02)
        #expect(abs(mapped.origin.x - whole.origin.x) < 0.01)
    }
}
