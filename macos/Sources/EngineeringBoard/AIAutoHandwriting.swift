import Foundation
import AppKit

/// Bounded local OCR after an idle pause. Preview only: original ink is never overwritten.
@MainActor
final class AutoHandwritingCoordinator: ObservableObject {
    @Published private(set) var previewText = ""
    @Published private(set) var suggestions: [AISpellingSuggestion] = []
    @Published private(set) var isReading = false
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var lastInk: [DrawingElement] = []
    private let preferences: UserDefaults
    private let readSnapshot: (Board, [DrawingElement]) async throws -> String

    init(preferences: UserDefaults = .standard,
         readSnapshot: ((Board, [DrawingElement]) async throws -> String)? = nil) {
        self.preferences = preferences
        self.readSnapshot = readSnapshot ?? { try await Handwriting.readSnapshot(board: $0, strokes: $1) }
    }

    var hasPreview: Bool { !previewText.isEmpty }

    func schedule(session: DrawingSession, isInputActive: @escaping () -> Bool = { false }) {
        guard preferences.object(forKey: "engineeringboard.handwriting.autoReview") as? Bool ?? true else {
            stop(); return
        }
        let ink = Array(session.board.elements.reversed().lazy.filter {
            $0.kind == .stroke && $0.points.count >= 3
        }.prefix(60).reversed())
        guard ink != lastInk else { return }
        lastInk = ink
        task?.cancel()
        let token = UUID(); generation = token
        let revision = session.revision
        let board = session.board
        guard !ink.isEmpty else { previewText = ""; suggestions = []; isReading = false; return }
        task = Task { [weak self, weak session] in
            guard let self, let session else { return }
            defer { if self.generation == token { self.isReading = false; self.task = nil } }
            do {
                try await Task.sleep(for: .milliseconds(2200))
                // A long new stroke may still be active without a committed revision.
                while isInputActive() || session.recognitionBusy {
                    try await Task.sleep(for: .milliseconds(250))
                }
                try Task.checkCancellation()
                guard self.preferences.object(forKey: "engineeringboard.handwriting.autoReview") as? Bool ?? true,
                      self.generation == token, session.board.id == board.id, session.revision == revision else { return }
                let bounded = Self.boundedInk(ink)
                guard !bounded.isEmpty else { return }
                self.isReading = true
                let text = try await self.readSnapshot(board, bounded)
                try Task.checkCancellation()
                while isInputActive() { try await Task.sleep(for: .milliseconds(250)) }
                guard self.preferences.object(forKey: "engineeringboard.handwriting.autoReview") as? Bool ?? true,
                      self.generation == token, session.board.id == board.id,
                      session.revision == revision else { return }
                self.previewText = text
                self.suggestions = AILocalSpelling.suggestions(in: text)
                session.recognizedText = text
            } catch { /* A cancelled or uncertain automatic read must not interrupt drawing. */ }
        }
    }

    static func boundedInk(_ input: [DrawingElement]) -> [DrawingElement] {
        var ink = Array(input.suffix(60))
        while ink.count > 1 && ink.reduce(0, { $0 + $1.points.count }) > 20_000 { ink.removeFirst() }
        guard ink.reduce(0, { $0 + $1.points.count }) <= 20_000 else { return [] }
        while ink.count > 1 {
            let bounds = ink.reduce(CGRect.null) { $0.union($1.bounds) }
            if bounds.width <= 4000 && bounds.height <= 2400 { return ink }
            ink.removeFirst()
        }
        if let single = ink.first, single.bounds.width <= 4000, single.bounds.height <= 2400 { return ink }
        return []
    }

    func stop() {
        generation = UUID(); task?.cancel(); task = nil; isReading = false
        lastInk = []
    }
}
