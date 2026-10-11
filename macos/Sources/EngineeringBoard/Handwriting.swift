import SwiftUI
import AppKit
import Vision

enum Handwriting {
    @MainActor
    static func strokeIDs(session: DrawingSession) -> Set<UUID> {
        let selection = session.selectedIDs
        return Set(session.board.elements.filter {
            $0.kind == .stroke && (selection.isEmpty || selection.contains($0.id))
        }.map(\.id))
    }

    @MainActor
    static func recognize(session: DrawingSession, strokeIDs requestedIDs: Set<UUID>? = nil) async -> String {
        session.finishActiveInput?()
        guard !session.recognitionBusy else { return session.recognizedText }
        session.recognitionBusy = true
        session.error = nil
        defer { session.recognitionBusy = false }
        let ids = requestedIDs ?? strokeIDs(session: session)
        let strokes = session.board.elements.filter { ids.contains($0.id) && $0.kind == .stroke }
        guard !strokes.isEmpty else {
            session.error = "Select some handwriting strokes, or clear the selection to read all ink."
            return ""
        }
        let source = session.board
        let revision = session.revision
        do {
            let text = try await readSnapshot(board: source, strokes: strokes)
            try Task.checkCancellation()
            guard session.board.id == source.id, session.revision == revision else {
                session.status = "The board changed while reading. Read the current handwriting again."
                return ""
            }
            session.recognizedText = text
            if text.isEmpty {
                session.error = "No readable text was found. Try larger, clearer handwriting."
            } else {
                session.status = "Local handwriting recognition • review the preview"
            }
            return text
        } catch is CancellationError { return "" }
        catch {
            session.error = "Local text recognition failed: \(error.localizedDescription)"
            return ""
        }
    }

    /// Recognition uses immutable ink on a utility task; rendering never blocks active UI ink.
    @MainActor
    static func readSnapshot(board: Board, strokes: [DrawingElement]) async throws -> String {
        guard !strokes.isEmpty else { return "" }
        let worker = Task.detached(priority: .utility) {
            guard let image = recognitionImage(strokes: strokes) else {
                throw AssistantConversation.APIError.message("The handwriting image couldn't be prepared.")
            }
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Avoid linguistic autocorrection changing units or engineering symbols.
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-GB", "en-US"]
            request.minimumTextHeight = 0.008
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            try Task.checkCancellation()
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    /// A bounded, high contrast OCR raster. Brush appearance and saved ink remain unchanged.
    nonisolated static func recognitionImage(strokes: [DrawingElement]) -> CGImage? {
        guard !strokes.isEmpty else { return nil }
        let bounds = strokes.reduce(CGRect.null) { $0.union($1.bounds) }.insetBy(dx: -28, dy: -28)
        guard !bounds.isNull, [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy({ $0.isFinite }) else { return nil }
        let worldWidth = max(120, bounds.width), worldHeight = max(100, bounds.height)
        let scale = min(1.5, 2560 / max(worldWidth, worldHeight))
        let width = min(2560, max(1, Int(ceil(worldWidth * scale))))
        let height = min(2560, max(1, Int(ceil(worldHeight * scale))))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setFillColor(gray: 0, alpha: 1)
        context.setLineCap(.round); context.setLineJoin(.round); context.setShouldAntialias(true)
        for stroke in strokes where stroke.kind == .stroke {
            guard let first = stroke.points.first else { continue }
            let lineWidth = max(0.7, min(stroke.width.isFinite ? stroke.width : 2, 24))
            context.setLineWidth(lineWidth)
            if stroke.points.count == 1 {
                context.fillEllipse(in: CGRect(x: first.x - lineWidth / 2, y: first.y - lineWidth / 2,
                                               width: lineWidth, height: lineWidth))
            } else {
                context.beginPath(); context.move(to: first.cg)
                for point in stroke.points.dropFirst() { context.addLine(to: point.cg) }
                context.strokePath()
            }
        }
        return context.makeImage()
    }

    @MainActor
    static func smoothSelection(session: DrawingSession) {
        let indices = session.board.elements.indices.filter {
            let element = session.board.elements[$0]
            return session.selectedIDs.contains(element.id) && element.kind == .stroke &&
                   !element.locked && element.points.count >= 3
        }
        guard !indices.isEmpty else {
            session.status = "Select handwritten strokes to smooth them"
            return
        }
        session.checkpoint()
        for index in indices {
            session.board.elements[index].points = smoothed(session.board.elements[index].points)
        }
        session.changed()
        session.status = "Selected ink smoothed locally • Undo restores the original"
    }

    // One gentle pass; endpoints, pressure and tilt are preserved. This is not OCR or AI.
    static func smoothed(_ points: [InkPoint]) -> [InkPoint] {
        guard points.count >= 3 else { return points }
        var result = points
        for index in 1..<(points.count - 1) {
            let before = points[index - 1], current = points[index], after = points[index + 1]
            result[index].x = 0.15 * before.x + 0.7 * current.x + 0.15 * after.x
            result[index].y = 0.15 * before.y + 0.7 * current.y + 0.15 * after.y
        }
        return result
    }
}

struct HandwritingPreview: View {
    @ObservedObject var session: DrawingSession
    @Environment(\.dismiss) private var dismiss
    @State<String> private var preview = ""
    @State<Set<UUID>> private var capturedStrokeIDs = Set<UUID>()
    @State private var suggestions: [AISpellingSuggestion] = []
    @State private var suggestionSource = ""
    @State private var showAdvancedReview = false

    private var selectedReplaceable: [DrawingElement] {
        session.board.elements.filter {
            capturedStrokeIDs.contains($0.id) && session.selectedIDs.contains($0.id) &&
            $0.kind == .stroke && !$0.locked
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Handwriting preview", systemImage: "text.viewfinder").font(.title2.weight(.semibold))
            Text("Apple Vision runs on this Mac. No image is sent to OpenAI. Text recognition may misread handwriting, numbers and symbols; check and edit the result before inserting it.")
                .font(.callout).foregroundStyle(.secondary)
            Text("This is text OCR, not a maths parser. Fractions, superscripts, Greek letters and circuit symbols may lose their layout.")
                .font(.caption).foregroundStyle(.secondary)
            if session.recognitionBusy {
                ProgressView("Reading local ink…").padding(.vertical, 20)
            }
            TextEditor(text: $preview)
                .font(.system(size: 18))
                .frame(minHeight: 230)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                .accessibilityLabel("Editable recognized handwriting preview")
            HStack {
                Button("Check spelling locally") {
                    suggestions = AILocalSpelling.suggestions(in: preview)
                    suggestionSource = preview
                }.disabled(session.recognitionBusy || preview.isEmpty)
                Button("Spelling & cloud review…") { showAdvancedReview = true }
                    .disabled(session.recognitionBusy || preview.isEmpty)
            }
            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { suggestion in
                            Menu {
                                ForEach(suggestion.alternatives, id: \.self) { word in
                                    Button(word) {
                                        if preview == suggestionSource,
                                           let updated = AILocalSpelling.replacing(suggestion, with: word, in: preview) {
                                            preview = updated
                                            suggestions = AILocalSpelling.suggestions(in: preview)
                                            suggestionSource = preview
                                        } else { suggestions = [] }
                                    }
                                }
                            } label: { Text(suggestion.word + " → " + (suggestion.alternatives.first ?? "")) }
                        }
                    }
                }.frame(height: 26)
            }
            if let error = session.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text("Replace removes only selected, unlocked ink. Undo restores your original strokes.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Read again") {
                    Task { preview = await Handwriting.recognize(session: session) }
                }.disabled(session.recognitionBusy)
                Spacer()
                Button("Replace selected ink") { insert(replace: true) }
                    .disabled(selectedReplaceable.isEmpty || preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.recognitionBusy)
                Button("Insert text") { insert(replace: false) }
                    .buttonStyle(.borderedProminent)
                    .disabled(preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.recognitionBusy)
            }
        }
        .padding(24)
        .frame(width: 660, height: 570)
        .sheet(isPresented: $showAdvancedReview) {
            AIHandwritingReview(session: session, initialText: preview, onApply: { preview = $0 })
        }
        .task {
            session.finishActiveInput?()
            capturedStrokeIDs = Handwriting.strokeIDs(session: session)
            preview = await Handwriting.recognize(session: session)
        }
    }

    private func insert(replace: Bool) {
        session.finishActiveInput?()
        let strokes = selectedReplaceable
        let related = session.board.elements.filter { capturedStrokeIDs.contains($0.id) }
        let bounds = related.reduce(CGRect.null) { $0.union($1.bounds) }
        let x = bounds.isNull ? session.cameraOffset.x + 60 / session.zoom : bounds.minX
        let y = bounds.isNull ? session.cameraOffset.y + 60 / session.zoom : bounds.minY
        let text = DrawingElement(kind: .text, points: [InkPoint(x: x, y: y)],
                                  color: session.color, text: preview, fontSize: 24)
        session.checkpoint()
        if replace {
            let ids = Set(strokes.map(\.id))
            session.board.elements.removeAll { ids.contains($0.id) }
        }
        session.board.elements.append(text)
        session.selectedIDs = [text.id]
        session.recognizedText = preview
        session.changed()
        session.status = "Reviewed handwriting inserted as text"
        dismiss()
    }
}
