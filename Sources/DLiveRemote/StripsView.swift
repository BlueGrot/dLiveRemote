import SwiftUI
import DLiveMIDI

struct StripsView: View {
    @EnvironmentObject var model: MixerModel
    let kind: ChannelKind

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 6) {
                ForEach(0..<kind.count, id: \.self) { i in
                    ChannelStrip(address: ChannelAddress(kind, i))
                }
            }
            .padding(10)
        }
    }
}

extension ChannelColour {
    var swiftUIColor: Color {
        switch self {
        case .off: return Color(white: 0.25)
        case .red: return .red
        case .green: return .green
        case .yellow: return .yellow
        case .blue: return .blue
        case .purple: return .purple
        case .lightBlue: return .cyan
        case .white: return .white
        }
    }
}

struct ChannelStrip: View {
    @EnvironmentObject var model: MixerModel
    let address: ChannelAddress
    @State private var editingName = false
    @State private var nameDraft = ""

    private var s: StripState { model.state(address) }
    private var colour: ChannelColour { ChannelColour(rawValue: s.colour) ?? .off }

    var body: some View {
        VStack(spacing: 6) {
            Text(address.description)
                .font(.caption2)
                .foregroundStyle(.secondary)

            nameLabel

            if address.kind.hasFader {
                VerticalFader(value: Binding(
                    get: { s.level },
                    set: { model.setLevel(address, $0) }
                ))
                .frame(width: 34, height: 200)

                Text(FaderLaw.label(for: s.level))
                    .font(.caption.monospacedDigit())
                    .frame(width: 52)
            }

            Button {
                model.toggleMute(address)
            } label: {
                Text("MUTE")
                    .font(.caption.bold())
                    .frame(width: 52, height: 22)
                    .background(s.muted ? Color.red : Color.secondary.opacity(0.2))
                    .foregroundStyle(s.muted ? Color.white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .frame(width: 70)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
        .contextMenu { contextMenu }
    }

    @ViewBuilder private var nameLabel: some View {
        if editingName {
            TextField("Name", text: $nameDraft, onCommit: {
                model.send(.setName(address, nameDraft))
                editingName = false
            })
            .font(.caption)
            .textFieldStyle(.roundedBorder)
            .frame(width: 64)
        } else {
            Text(s.name.isEmpty ? " " : s.name)
                .font(.caption.bold())
                .lineLimit(1)
                .frame(width: 60, height: 18)
                .background(address.kind.hasNameAndColour ? colour.swiftUIColor.opacity(0.85) : .clear)
                .foregroundStyle(colour == .yellow || colour == .white || colour == .lightBlue ? Color.black : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .onTapGesture(count: 2) {
                    guard address.kind.hasNameAndColour else { return }
                    nameDraft = s.name
                    editingName = true
                }
        }
    }

    @ViewBuilder private var contextMenu: some View {
        if address.kind.hasNameAndColour {
            Button("Rename…") { nameDraft = s.name; editingName = true }
            Menu("Colour") {
                ForEach(ChannelColour.allCases) { c in
                    Button(c.name) { model.send(.setColour(address, c)) }
                }
            }
        }
        if address.kind.hasFader {
            Button("Set to 0 dB") { model.setLevel(address, FaderLaw.unity) }
            Button("Set to -∞") { model.setLevel(address, 0) }
        }
        if address.kind != .dca && address.kind != .muteGroup {
            Menu("Assign DCA") {
                ForEach(0..<24, id: \.self) { d in
                    Button("DCA \(d + 1)") { model.send(.dcaAssign(address, dca: d, assigned: true)) }
                }
            }
            Menu("Unassign DCA") {
                ForEach(0..<24, id: \.self) { d in
                    Button("DCA \(d + 1)") { model.send(.dcaAssign(address, dca: d, assigned: false)) }
                }
            }
            Menu("Mute Groups") {
                ForEach(0..<8, id: \.self) { g in
                    Button("Assign MG \(g + 1)") { model.send(.muteGroupAssign(address, group: g, assigned: true)) }
                }
                Divider()
                ForEach(0..<8, id: \.self) { g in
                    Button("Unassign MG \(g + 1)") { model.send(.muteGroupAssign(address, group: g, assigned: false)) }
                }
            }
        }
        Divider()
        Button("Get state from mixer") {
            if address.kind.hasNameAndColour {
                model.send(.getName(address)); model.send(.getColour(address))
            }
            if address.kind.hasFader { model.send(.getLevel(address)) }
            model.send(.getMute(address))
        }
    }
}

/// Simple vertical fader mapped to the 0...127 MIDI value.
struct VerticalFader: View {
    @Binding var value: UInt8

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let capH: CGFloat = 22
            let travel = h - capH
            let y = travel * (1 - CGFloat(value) / 127)
            let unityY = travel * (1 - CGFloat(FaderLaw.unity) / 127) + capH / 2

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, capH / 2)
                Rectangle()
                    .fill(Color.secondary)
                    .frame(width: 18, height: 1)
                    .offset(y: unityY)
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)], startPoint: .top, endPoint: .bottom))
                    .overlay(Rectangle().fill(Color.black.opacity(0.6)).frame(height: 1))
                    .frame(width: 30, height: capH)
                    .offset(y: y)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let pos = min(max(g.location.y - capH / 2, 0), travel)
                        let v = UInt8((127 * (1 - pos / travel)).rounded())
                        if v != value { value = v }
                    }
            )
        }
    }
}
