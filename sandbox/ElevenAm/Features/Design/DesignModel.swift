import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UniformTypeIdentifiers
import Vision

enum GraphicTemplate: String, CaseIterable, Identifiable {
    case announcement, quote, stat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .announcement: return "Announcement"
        case .quote: return "Quote"
        case .stat: return "Big number"
        }
    }
}

enum GraphicSize: String, CaseIterable, Identifiable {
    case square, portrait, landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .square: return "Square · 1080"
        case .portrait: return "Portrait · 4:5"
        case .landscape: return "Link · 1200×630"
        }
    }

    var pixels: CGSize {
        switch self {
        case .square: return CGSize(width: 1080, height: 1080)
        case .portrait: return CGSize(width: 1080, height: 1350)
        case .landscape: return CGSize(width: 1200, height: 630)
        }
    }
}

enum ImageToolError: LocalizedError {
    case unreadable, noSubject, render

    var errorDescription: String? {
        switch self {
        case .unreadable: return "That image couldn't be read."
        case .noSubject: return "Robert couldn't find a clear subject in that image."
        case .render: return "The result couldn't be rendered."
        }
    }
}

/// Image work that runs off the main thread, entirely on this Mac.
enum ImageTools {
    /// Lifts the subject out of its background with Vision (the same engine as Photos).
    static func liftSubject(from image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else { throw ImageToolError.noSubject }
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
        let output = CIImage(cvPixelBuffer: buffer)
        guard let result = CIContext().createCGImage(output, from: output.extent) else { throw ImageToolError.render }
        return result
    }

    /// A rich black-and-white conversion with a touch of grain, in keeping with the 11am look.
    static func monochrome(_ image: CGImage) throws -> CGImage {
        let input = CIImage(cgImage: image)
        let noir = CIFilter.photoEffectNoir()
        noir.inputImage = input
        guard var output = noir.outputImage else { throw ImageToolError.render }
        let grain = CIFilter.randomGenerator().outputImage?
            .cropped(to: input.extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.06),
            ])
        if let grain {
            output = grain.composited(over: output)
        }
        guard let result = CIContext().createCGImage(output, from: input.extent) else { throw ImageToolError.render }
        return result
    }

    static func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// Robert in the sandbox: the brand kit every agent uses, quick on-brand graphics, and image tools on this Mac.
@MainActor
final class DesignModel: ObservableObject {
    @Published var template: GraphicTemplate = .announcement
    @Published var size: GraphicSize = .square
    @Published var headline = "We closed our first enterprise pilot."
    @Published var detail = "Acme is rolling 11am out to 40 people this month."
    @Published var footer = "11am.app"
    @Published var dark = false
    @Published var showsMark = true
    @Published private(set) var headlineRun: BrainRun?

    @Published private(set) var original: CGImage?
    @Published private(set) var result: CGImage?
    @Published private(set) var isProcessing = false
    @Published var imageNotice: String?

    private let brain: Brain

    init(brain: Brain) {
        self.brain = brain
    }

    func suggestHeadlines() {
        let system = """
        You are Robert, the design agent inside 11am. Write five short headlines for a social graphic, one per line, \
        no numbering, no quotes, no emoji. Under ten words each. Plain and confident.
        """
        let prompt = "Template: \(template.title)\nCurrent headline: \(headline)\nSupporting line: \(detail)"
        headlineRun = brain.run(BrainRequest(system: system, prompt: prompt, weight: .quick))
    }

    static func headlines(in text: String) -> [String] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-•*0123456789. \"").union(.whitespaces)) }
            .filter { !$0.isEmpty }
            .prefix(5)
            .map { $0 }
    }

    // MARK: Image tools

    func load(_ url: URL) {
        guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            imageNotice = ImageToolError.unreadable.localizedDescription
            return
        }
        original = image
        result = nil
        imageNotice = nil
    }

    func liftSubject() { process { try ImageTools.liftSubject(from: $0) } }

    func monochrome() { process { try ImageTools.monochrome($0) } }

    private func process(_ work: @escaping @Sendable (CGImage) throws -> CGImage) {
        guard let source = result ?? original else { return }
        isProcessing = true
        imageNotice = nil
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<CGImage, Error> in
                Result { try work(source) }
            }.value
            isProcessing = false
            switch outcome {
            case .success(let image): result = image
            case .failure(let error): imageNotice = error.localizedDescription
            }
        }
    }

    func resetImage() {
        result = nil
    }

    func saveResult() {
        guard let image = result ?? original, let data = ImageTools.pngData(image) else { return }
        DesignModel.save(data, suggestedName: "11am-image.png")
    }

    /// Asks where to save, then writes the file.
    static func save(_ data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedName
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}
