import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import Darwin

enum BoardFileError: LocalizedError {
    case invalid(String)
    case tooLarge
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .invalid(let reason): return "This drawing can't be opened or saved: \(reason)"
        case .tooLarge: return "This drawing file is larger than the supported 256 MB limit. The original file has been kept."
        case .unsupportedVersion(let version): return "This drawing uses file version \(version). This app supports version 1. The original file has been kept."
        }
    }
}

/// Validates file input before it reaches the renderer. It never edits the input.
enum BoardFile {
    static let maximumBytes = 256 * 1024 * 1024
    static let maximumTotalImageBytes = 128 * 1024 * 1024
    static let projectType = UTType(exportedAs: "com.engineeringboard.drawing", conformingTo: .json)

    static func validate(_ board: Board) throws {
        guard board.version == 1 else { throw BoardFileError.unsupportedVersion(board.version) }
        guard board.width.isFinite, board.height.isFinite,
              board.width >= 1, board.height >= 1, board.width <= 30_000, board.height <= 30_000 else {
            throw BoardFileError.invalid("the canvas dimensions must be between 1 and 30,000 drawing points.")
        }
        guard board.pointsPerMM.isFinite, (0.01...1_000_000).contains(board.pointsPerMM),
              board.scaleDenominator.isFinite, (0.001...1_000_000).contains(board.scaleDenominator),
              board.gridSpacing.isFinite, (1...1_000_000).contains(board.gridSpacing) else {
            throw BoardFileError.invalid("the drawing scale or grid spacing is not valid.")
        }
        guard board.elements.count <= 100_000 else { throw BoardFileError.invalid("there are too many objects.") }
        var totalPoints = 0
        var totalImageBytes = 0
        var identifiers = Set<UUID>()
        for element in board.elements {
            if let imageData = element.imageData {
                totalImageBytes += imageData.count
                guard totalImageBytes <= maximumTotalImageBytes else {
                    throw BoardFileError.invalid("embedded images exceed the 128 MB per-drawing limit.")
                }
                do { try SafeImage.validate(imageData) }
                catch { throw BoardFileError.invalid(error.localizedDescription) }
            }
            if let sketch = element.sketch3D {
                guard element.kind == .image, element.imageData != nil else {
                    throw BoardFileError.invalid("an editable 3D scene must belong to an image object.")
                }
                try Sketch3DFile.validate(sketch)
            }
            guard identifiers.insert(element.id).inserted else {
                throw BoardFileError.invalid("two objects have the same identifier.")
            }
            totalPoints += element.points.count
            guard totalPoints <= 2_000_000 else { throw BoardFileError.invalid("there are too many pen points.") }
            guard element.width.isFinite, element.width > 0, element.width <= 1_000,
                  element.fontSize.isFinite, element.fontSize > 0, element.fontSize <= 1_000,
                  element.rotation.isFinite else {
                throw BoardFileError.invalid("an object has an invalid pen width, text size or rotation.")
            }
            let channels = [element.color.r, element.color.g, element.color.b, element.color.a]
            guard channels.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                throw BoardFileError.invalid("an object has an invalid colour.")
            }
            if let brush = element.brushSettings {
                guard brush.minWidth.isFinite, brush.maxWidth.isFinite,
                      brush.minWidth > 0, brush.maxWidth >= brush.minWidth, brush.maxWidth <= 1_000,
                      brush.opacity.isFinite, (0...1).contains(brush.opacity),
                      brush.minOpacity.isFinite, brush.maxOpacity.isFinite,
                      (0...1).contains(brush.minOpacity), (brush.minOpacity...1).contains(brush.maxOpacity),
                      brush.pressureGamma.isFinite, (0.15...4).contains(brush.pressureGamma),
                      brush.textureScale.isFinite, (0.1...5).contains(brush.textureScale) else {
                    throw BoardFileError.invalid("an object has invalid brush or pressure settings.")
                }
            }
            guard element.points.allSatisfy({
                $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 &&
                $0.pressure.isFinite && (0...1).contains($0.pressure) && $0.tiltX.isFinite && $0.tiltY.isFinite &&
                ($0.velocity == nil || ($0.velocity!.isFinite && $0.velocity! >= 0))
                && ($0.rawPressure == nil || ($0.rawPressure!.isFinite && (0...1).contains($0.rawPressure!)))
                && ($0.inputDeviceKey == nil || $0.inputDeviceKey!.utf8.count <= 255)
            }) else {
                throw BoardFileError.invalid("an object contains invalid coordinates or pressure values.")
            }
        }
    }

    static func encode(_ board: Board) throws -> Data {
        try validate(board)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(board)
        guard data.count <= maximumBytes else { throw BoardFileError.tooLarge }
        return data
    }

    static func read(from url: URL) throws -> Board {
        try decode(data(from: url))
    }

    static func data(from url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes else { throw BoardFileError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumBytes else { throw BoardFileError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> Board {
        guard data.count <= maximumBytes else { throw BoardFileError.tooLarge }
        let board = try JSONDecoder().decode(Board.self, from: data)
        try validate(board)
        return board
    }

    static func filename(for title: String, extension suffix: String) -> String {
        let prohibited = CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)
        let cleaned = title.components(separatedBy: prohibited).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(cleaned.isEmpty ? "Drawing" : String(cleaned.prefix(120))).\(suffix)"
    }
}

@MainActor
final class BoardStore: ObservableObject {
    @Published var boards: [Board] = []
    @Published var error: String?
    @Published var conflictingBoardID: UUID?
    let directory: URL
    private var fileFingerprints: [UUID: String] = [:]
    private var pendingAutosave: Board?
    private var encodingAutosave: Board?
    private var autosaveTask: Task<Void, Never>?
    private var autosaveGeneration = 0
    private var pendingSince: TimeInterval = 0
    private var lastScheduled: TimeInterval = 0
    private(set) var completedAutosaves = 0
    private(set) var lastReloadDecodedBoards = 0
    private(set) var lastReloadReusedBoards = 0
    var archiveDirectory: URL { directory.appendingPathComponent("Archive", isDirectory: true) }

    init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.directory = directory ?? base.appendingPathComponent("EngineeringBoard/Boards", isDirectory: true)
        let firstLaunch = directory == nil && !FileManager.default.fileExists(atPath: self.directory.path)
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            try load()
            if firstLaunch { save(Self.demoBoard()) }
        } catch {
            self.error = "Couldn't open the local drawing library. \(error.localizedDescription)"
        }
    }

    func url(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("engboard") }

    private func load() throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                               options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "engboard" }
        var loaded: [Board] = []
        var problems: [String] = []
        var ids = Set<UUID>()
        var loadedFingerprints: [UUID: String] = [:]
        let knownBoards = Dictionary(boards.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        lastReloadDecodedBoards = 0; lastReloadReusedBoards = 0
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let data = try BoardFile.data(from: file)
                // Compare actual bytes, rather than modification dates. An external
                // editor can replace a file without changing its timestamp or size.
                let fingerprint = Self.fingerprint(data)
                let filenameID = UUID(uuidString: file.deletingPathExtension().lastPathComponent)
                let board: Board
                if let id = filenameID, let known = knownBoards[id], fileFingerprints[id] == fingerprint {
                    board = known; lastReloadReusedBoards += 1
                } else {
                    board = try BoardFile.decode(data); lastReloadDecodedBoards += 1
                }
                // Prevent a renamed or duplicate file being overwritten by the next save.
                guard file.lastPathComponent == url(for: board.id).lastPathComponent else {
                    throw BoardFileError.invalid("the library filename doesn't match its drawing identifier. Use Import Drawing to copy this file safely.")
                }
                guard ids.insert(board.id).inserted else {
                    throw BoardFileError.invalid("a duplicate drawing identifier was found.")
                }
                loaded.append(board)
                loadedFingerprints[board.id] = fingerprint
            } catch {
                problems.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        boards = loaded.sorted { $0.modified > $1.modified }
        fileFingerprints = loadedFingerprints
        if !problems.isEmpty {
            error = "Some drawing files couldn't be opened. They have been left untouched in \(directory.path).\n\n" + problems.joined(separator: "\n")
        }
    }

    /// Reload is a deliberate recovery action. It does not save an older in-memory session.
    @discardableResult
    func reload() -> Bool {
        cancelAutosave()
        do {
            error = nil
            try load()
            conflictingBoardID = nil
            return true
        } catch {
            self.error = "Couldn't reload the drawing library. \(error.localizedDescription)"
            return false
        }
    }

    /// Writes the complete drawing atomically before changing the visible library.
    /// Called when an edit finishes, so a closed window has no queued unsaved snapshot.
    @discardableResult
    func save(_ board: Board) -> Bool {
        cancelAutosave()
        do {
            try persist(board)
            if conflictingBoardID == board.id { conflictingBoardID = nil }
            error = nil
            return true
        } catch {
            self.error = "Couldn't save ‘\(board.title)’. The previous saved drawing has been kept. \(error.localizedDescription)"
            return false
        }
    }

    /// Keep one latest snapshot. Encoding runs off the drawing thread after a
    /// short pause, or at least every three seconds during continuous edits.
    /// Explicit Save/navigation/close still call save(_:) synchronously.
    func scheduleSave(_ board: Board) {
        let now = ProcessInfo.processInfo.systemUptime
        if pendingAutosave == nil { pendingSince = now }
        pendingAutosave = board; lastScheduled = now
        guard autosaveTask == nil else { return }
        let generation = autosaveGeneration
        autosaveTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.autosaveGeneration == generation {
                    self.autosaveTask = nil; self.encodingAutosave = nil
                }
            }
            while self.autosaveGeneration == generation, !Task.isCancelled,
                  self.pendingAutosave != nil {
                let now = ProcessInfo.processInfo.systemUptime
                let wait = max(0, min(self.lastScheduled + 0.7, self.pendingSince + 3) - now)
                if wait > 0 {
                    do { try await Task.sleep(for: .seconds(wait)) } catch { return }
                    continue
                }
                guard let snapshot = self.pendingAutosave else { return }
                self.pendingAutosave = nil; self.encodingAutosave = snapshot
                let result = await Task.detached(priority: .utility) { Result { try BoardFile.encode(snapshot) } }.value
                guard self.autosaveGeneration == generation, !Task.isCancelled else { return }
                self.encodingAutosave = nil
                do {
                    try self.persist(snapshot, encodedData: result.get())
                    self.completedAutosaves += 1
                    if self.conflictingBoardID == snapshot.id { self.conflictingBoardID = nil }
                    self.error = nil
                } catch {
                    self.error = "Couldn't save ‘\(snapshot.title)’. The previous saved drawing has been kept. \(error.localizedDescription)"
                    // Keep the newest edits for explicit recovery; do not retry
                    // a conflict in a loop or replace the external saved version.
                    self.cancelAutosave()
                    return
                }
            }
        }
    }

    private func cancelAutosave() {
        autosaveGeneration += 1
        autosaveTask?.cancel(); autosaveTask = nil
        pendingAutosave = nil; encodingAutosave = nil
    }

    private func persist(_ board: Board, encodedData: Data? = nil) throws {
        let data = try encodedData ?? BoardFile.encode(board)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let locks = directory.appendingPathComponent(".locks", isDirectory: true)
        try FileManager.default.createDirectory(at: locks, withIntermediateDirectories: true)
        let descriptor = Darwin.open(locks.appendingPathComponent(board.id.uuidString + ".lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw SaveConflictFailure.busy
        }
        defer { flock(descriptor, LOCK_UN) }
        let target = url(for: board.id)
        let existingData: Data?
        if FileManager.default.fileExists(atPath: target.path) {
            existingData = try BoardFile.data(from: target)
        } else { existingData = nil }
        let existingFingerprint = existingData.map(Self.fingerprint)
        if existingFingerprint != fileFingerprints[board.id] {
            // Identical semantic content is harmless, even if another instance serialized it differently.
            let identical = existingData.flatMap { try? BoardFile.decode($0) } == board
            if !identical {
                conflictingBoardID = board.id
                let conflictDirectory = archiveDirectory.appendingPathComponent("Conflicts", isDirectory: true)
                    .appendingPathComponent(board.id.uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: conflictDirectory, withIntermediateDirectories: true)
                try preserveConflict(data, named: "incoming", in: conflictDirectory)
                if let existingData { try preserveConflict(existingData, named: "saved", in: conflictDirectory) }
                throw SaveConflictFailure.changed
            }
        }
        try data.write(to: url(for: board.id), options: .atomic)
        fileFingerprints[board.id] = Self.fingerprint(data)
        if let index = boards.firstIndex(where: { $0.id == board.id }) { boards[index] = board }
        else { boards.append(board) }
        boards.sort { $0.modified > $1.modified }
    }

    private static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func preserveConflict(_ data: Data, named role: String, in folder: URL) throws {
        let file = folder.appendingPathComponent(role + "-" + Self.fingerprint(data)).appendingPathExtension("engboard")
        if FileManager.default.fileExists(atPath: file.path) { return }
        try data.write(to: file, options: .withoutOverwriting)
    }

    private enum SaveConflictFailure: LocalizedError {
        case changed, busy
        var errorDescription: String? {
            switch self {
            case .changed: return "Another app instance changed or removed this drawing. The saved version wasn't overwritten. Your incoming edits and any saved version were preserved under Archive/Conflicts. Save your edits as a new drawing, or deliberately reload the saved version."
            case .busy: return "Another app instance is saving this drawing. Try saving again in a moment."
            }
        }
    }

    @discardableResult
    func create(title: String = "Untitled drawing", background: BackgroundKind = .grid, folder: String = "General") -> Board {
        var board = Board()
        board.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled drawing" : title
        board.background = background
        board.folder = folder
        save(board)
        return board
    }

    @discardableResult
    func duplicate(_ board: Board) -> Board {
        var copy = board
        copy.id = UUID()
        copy.title = board.title + " copy"
        copy.created = Date()
        copy.modified = copy.created
        copy.elements = board.elements.map { element in var item = element; item.id = UUID(); return item }
        save(copy)
        return copy
    }

    /// Deletion archives the actual last saved file; it never destroys it.
    func delete(_ board: Board) {
        let latest = pendingAutosave?.id == board.id ? pendingAutosave : (encodingAutosave?.id == board.id ? encodingAutosave : nil)
        if let latest, !save(latest) { return }
        cancelAutosave()
        do {
            try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
            let archived = archiveDirectory.appendingPathComponent("\(board.id.uuidString)-\(UUID().uuidString).engboard")
            let source = url(for: board.id)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.moveItem(at: source, to: archived)
            } else {
                try BoardFile.encode(board).write(to: archived, options: .atomic)
            }
            boards.removeAll { $0.id == board.id }
            fileFingerprints.removeValue(forKey: board.id)
            error = nil
        } catch {
            self.error = "Couldn't archive ‘\(board.title)’. It has been kept in your library. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func importBoard() -> Board? {
        let panel = NSOpenPanel()
        panel.title = "Import an editable drawing"
        panel.allowedContentTypes = [BoardFile.projectType, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let board = try importBoard(from: url)
            error = nil
            return board
        } catch {
            self.error = "Couldn't import the drawing. The original file has been kept. \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func importBoard(from url: URL) throws -> Board {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var board = try BoardFile.read(from: url)
        // Import is always a new drawing, including imports of a previous export.
        board.id = UUID()
        board.modified = Date()
        board.elements = board.elements.map { element in var item = element; item.id = UUID(); return item }
        try persist(board)
        return board
    }

    func exportProject(_ board: Board) {
        let panel = NSSavePanel()
        panel.title = "Export an editable drawing"
        panel.allowedContentTypes = [BoardFile.projectType]
        panel.nameFieldStringValue = BoardFile.filename(for: board.title, extension: "engboard")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try BoardFile.encode(board).write(to: url, options: .atomic)
            error = nil
        } catch {
            self.error = "Couldn't export ‘\(board.title)’. \(error.localizedDescription)"
        }
    }

    /// A labelled sample, not a record of work or verified engineering work.
    static func demoBoard() -> Board {
        var board = Board()
        board.title = "Engineering demo"
        board.background = .engineering
        board.notes = "Demo drawing only. Dimensions illustrate the app's scale tools and aren't manufacturing instructions. Replace this with your own brief, dimensions and evidence."
        func point(_ x: Double, _ y: Double) -> InkPoint { InkPoint(x: x, y: y) }
        func label(_ text: String, _ x: Double, _ y: Double, size: Double = 24, color: InkColor = .graphite) -> DrawingElement {
            DrawingElement(kind: .text, points: [point(x, y)], color: color, text: text, fontSize: size)
        }
        board.elements = [
            label("ENGINEERING DEMO", 100, 80, size: 40, color: .blue),
            label("Try a tool, change the paper, then save your own drawing.", 100, 145, size: 23),
            label("2D plate · example only · drawing scale 1:1", 100, 220, size: 24),
            DrawingElement(kind: .rectangle, points: [point(160, 340), point(760, 740)], color: .blue, width: 4),
            DrawingElement(kind: .ellipse, points: [point(250, 430), point(370, 550)], color: .blue, width: 4),
            DrawingElement(kind: .ellipse, points: [point(550, 430), point(670, 550)], color: .blue, width: 4),
            DrawingElement(kind: .line, points: [point(125, 490), point(790, 490)], color: .teal, width: 2, dash: "Centre"),
            DrawingElement(kind: .dimension, points: [point(160, 800), point(760, 800)], color: .graphite, width: 2),
            DrawingElement(kind: .dimension, points: [point(830, 340), point(830, 740)], color: .graphite, width: 2),
            label("Maths notes", 1020, 250, size: 32, color: .teal),
            label("Area = length × width\nA = 150 mm × 100 mm\nA = 15,000 mm²", 1020, 320, size: 28),
            label("Hole diameter = 30 mm\nDimensions shown are demo values.", 1020, 485, size: 24),
            label("Notes, ink and drawings save locally.\nPDF export keeps the chosen drawing scale.\nPrint the PDF at 100% / Actual Size.", 1020, 675, size: 24),
            label("Use the home screen to reopen your saved drawings.", 110, 995, size: 25, color: .blue)
        ]
        return board
    }
}
