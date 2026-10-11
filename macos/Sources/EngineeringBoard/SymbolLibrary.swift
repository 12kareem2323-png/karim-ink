import SwiftUI
import AppKit

struct SymbolLibrary: View {
    @ObservedObject var session: DrawingSession
    @State private var query = ""
    @State private var category: SymbolCategory?
    @AppStorage("engineeringboard.symbolAnimations") private var animate = true
    @State private var selection: SymbolDefinition?
    @State private var stampOnClick = true
    @Environment(\.scenePhase) private var scenePhase
    private let columns = [GridItem(.flexible(minimum: 100), spacing: 8), GridItem(.flexible(minimum: 100), spacing: 8)]
    private var matches: [SymbolDefinition] { SymbolCatalog.search(query, category: category) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Symbols and diagrams").font(.headline)
            Text("\(SymbolCatalog.all.count) drawing aids. Click or drag to insert.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search names, topics or symbols", text: $query).textFieldStyle(.roundedBorder)
            }
            Picker("Topic", selection: $category) {
                Text("All topics").tag(Optional<SymbolCategory>.none)
                ForEach(SymbolCategory.allCases) { category in Text(category.rawValue).tag(Optional(category)) }
            }
            Toggle("Animate dropped diagrams", isOn: $animate).toggleStyle(.checkbox).font(.caption)
            Toggle("Place at next canvas click", isOn: $stampOnClick).toggleStyle(.checkbox).font(.caption)
            if let id = session.pendingStampSymbolID, let symbol = SymbolCatalog.definition(id: id) {
                HStack {
                    Text("Stamping \(symbol.name). Esc returns to drawing.").font(.caption).foregroundStyle(.teal)
                    Button("Cancel") { session.pendingStampSymbolID = nil }.controlSize(.small)
                }
            }
            if let selected = selection {
                VStack(alignment: .leading, spacing: 7) {
                    TimelineView(.animation(minimumInterval: 1.0/30.0, paused: !animate || !selected.diagram.animated || scenePhase != .active)) { timeline in
                        let phase = animate ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2)/2 : 0
                        Image(nsImage: DiagramRenderer.image(definition: selected, size: CGSize(width: 140, height: 105), color: .labelColor, phase: phase))
                            .resizable().frame(width: 140, height: 105).frame(maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selected.name).font(.headline)
                        Text(selected.category.topic).foregroundStyle(.secondary)
                        Text(selected.source).font(.caption).foregroundStyle(.secondary)
                        Button("Insert into drawing") { insert(selected) }.buttonStyle(.borderedProminent)
                    }
                }.padding(9).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Text("\(matches.count) results").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(matches) { item in
                        VStack(spacing: 7) {
                            Button {
                                insert(item)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(nsImage: DiagramRenderer.image(definition: item, size: CGSize(width: 130, height: 98), color: .labelColor))
                                        .resizable().scaledToFit().frame(height: 90).frame(maxWidth: .infinity)
                                    Text(item.name).font(.caption2).lineLimit(2).frame(height: 30).frame(maxWidth: .infinity)
                                }
                            }.buttonStyle(.plain)
                                .onDrag { NSItemProvider(object: "engineeringboard-symbol:\(item.id)" as NSString) }
                                .help("Insert \(item.name), or drag it onto your drawing")
                            HStack {
                                Text(item.category.rawValue).font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Button { selection = item } label: { Image(systemName: "info.circle") }.buttonStyle(.plain)
                                    .help("Preview \(item.name)")
                            }
                        }
                        .padding(7)
                        .background(selection?.id == item.id ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    }
                }
                if matches.isEmpty { Text("No matching symbol. Try a shorter name or another topic.").foregroundStyle(.secondary).padding(30) }
            }
            DisclosureGroup("Conventions and references") {
                Text("Teaching diagrams. Check the convention your brief requires. Movement is illustrative.").font(.caption2).foregroundStyle(.secondary)
                ForEach(SymbolCatalog.referenceURLs, id: \.1) { reference in
                    if let url = URL(string: reference.1) { Link(reference.0, destination: url).font(.caption2) }
                }
            }
        }.padding(12)
    }

    private func insert(_ definition: SymbolDefinition) {
        if stampOnClick {
            session.tool = .ink
            session.pendingStampSymbolID = definition.id
            session.status = "Click the canvas to stamp \(definition.name) • Esc to draw"
            return
        }
        let size = definition.diagram == .glyph ? CGSize(width: 180, height: 135) : CGSize(width: 260, height: 195)
        let offset = Double(session.board.elements.count % 9) * 22
        let x = session.cameraOffset.x + 90 + offset
        let y = session.cameraOffset.y + 90 + offset
        let element = DrawingElement(kind: .symbol,
                                     points: [InkPoint(x: x, y: y), InkPoint(x: x + size.width, y: y + size.height)],
                                     color: session.color, width: session.lineWidth, text: "catalog:\(definition.id)")
        session.add(element, select: false)
        session.status = "Inserted \(definition.name)"
    }
}
