import SwiftUI
import DLiveMIDI

/// MixRack socket preamps 1–64 (MP 00–3F): gain, pad and 48V.
struct PreampsView: View {
    @EnvironmentObject var model: MixerModel

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 8) {
                ForEach(0..<64, id: \.self) { i in
                    PreampCell(socket: PreampSocket(mp: UInt8(i)))
                }
            }
            .padding(10)
        }
    }
}

struct PreampCell: View {
    @EnvironmentObject var model: MixerModel
    let socket: PreampSocket

    var body: some View {
        let p = model.preamp(socket)
        VStack(spacing: 6) {
            HStack {
                Text(socket.description).font(.caption.bold())
                Spacer()
                Text("\(PreampGainLaw.label(for: p.gain)) dB")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { Double(p.gain) },
                set: { model.setGain(socket, UInt8($0.rounded())) }
            ), in: 0...127)
            .controlSize(.small)
            HStack(spacing: 6) {
                toggleButton("PAD", on: p.pad, tint: .orange) { model.send(.preampPad(socket, !p.pad)) }
                toggleButton("48V", on: p.phantom, tint: .red) { model.send(.preamp48V(socket, !p.phantom)) }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }

    private func toggleButton(_ title: String, on: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .frame(maxWidth: .infinity, minHeight: 20)
                .background(on ? tint : Color.secondary.opacity(0.2))
                .foregroundStyle(on ? Color.white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}
