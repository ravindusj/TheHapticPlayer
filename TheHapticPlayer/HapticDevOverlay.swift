import SwiftUI

struct HapticDevOverlay: View {
    let session: HapticDevSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            waveformSection
            eventListSection
        }
        .padding(12)
        .background(.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .compositingGroup()
        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.currentIntensity > 0.05 ? Color.green : Color.green.opacity(0.35))
                .frame(width: 6, height: 6)
                .animation(.easeOut(duration: 0.15), value: session.currentIntensity)
            Text("HAPTIC DEBUG")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.85))
                .tracking(1.0)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(session.firedCount) / \(session.events.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                Text("FIRED / TOTAL")
                    .font(.system(size: 7, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private var waveformSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("LIVE POWER")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("\(Int(session.currentIntensity * 100))%")
                    .font(.system(size: 8, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: session.currentIntensity)
            }
            waveform
        }
    }

    private var waveform: some View {
        Canvas { context, size in
            let samples = session.waveform
            guard samples.count > 1 else { return }

            let height = size.height
            let width = size.width
            let stepX = width / CGFloat(samples.count - 1)
            let baseline = height / 2

            // Center reference line
            var ref = Path()
            ref.move(to: CGPoint(x: 0, y: baseline))
            ref.addLine(to: CGPoint(x: width, y: baseline))
            context.stroke(
                ref,
                with: .color(.white.opacity(0.08)),
                style: StrokeStyle(lineWidth: 0.5, dash: [2, 3])
            )

            // Build the waveform path (mirrored above + below the baseline).
            var top = Path()
            var bottom = Path()
            top.move(to: CGPoint(x: 0, y: baseline))
            bottom.move(to: CGPoint(x: 0, y: baseline))

            for (idx, raw) in samples.enumerated() {
                let value = max(0, min(1, raw))
                let x = CGFloat(idx) * stepX
                let halfAmp = CGFloat(value) * (height * 0.46)
                top.addLine(to: CGPoint(x: x, y: baseline - halfAmp))
                bottom.addLine(to: CGPoint(x: x, y: baseline + halfAmp))
            }

            // Filled body between top and bottom.
            var fill = top
            for (idx, raw) in samples.enumerated().reversed() {
                let value = max(0, min(1, raw))
                let x = CGFloat(idx) * stepX
                let halfAmp = CGFloat(value) * (height * 0.46)
                fill.addLine(to: CGPoint(x: x, y: baseline + halfAmp))
            }
            fill.closeSubpath()

            let tint = sharpnessColor(session.currentSharpness)
            context.fill(fill, with: .color(tint.opacity(0.35)))
            context.stroke(top, with: .color(tint.opacity(0.95)), lineWidth: 1.2)
            context.stroke(bottom, with: .color(tint.opacity(0.55)), lineWidth: 1.2)

            // Live cursor at the right edge.
            let cursorX = width - 0.5
            var cursor = Path()
            cursor.move(to: CGPoint(x: cursorX, y: 0))
            cursor.addLine(to: CGPoint(x: cursorX, y: height))
            context.stroke(cursor, with: .color(.white.opacity(0.5)), lineWidth: 0.5)
        }
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var eventListSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("RECENT EVENTS")
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.5))
            eventList
        }
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 4) {
            if session.recentlyFired.isEmpty {
                Text("waiting for events…")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.vertical, 2)
            } else {
                ForEach(Array(session.recentlyFired.enumerated()), id: \.element.id) { idx, event in
                    eventRow(event)
                        .opacity(opacityForRow(idx, count: session.recentlyFired.count))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.firedCount)
    }

    private func eventRow(_ event: HapticEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: event.kind == .transient ? "circle.fill" : "rectangle.fill")
                .font(.system(size: 7))
                .foregroundStyle(sharpnessColor(event.sharpness))
                .frame(width: 8)

            Text(formatTime(event.time))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 56, alignment: .leading)

            // Inline intensity bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(sharpnessColor(event.sharpness).opacity(0.85))
                        .frame(width: max(2, geo.size.width * CGFloat(event.intensity)))
                }
            }
            .frame(height: 5)

            Text("\(Int(event.intensity * 100))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 22, alignment: .trailing)
        }
    }

    private func opacityForRow(_ idx: Int, count: Int) -> Double {
        guard count > 1 else { return 1.0 }
        let normalized = Double(idx) / Double(count - 1)
        return 1.0 - normalized * 0.55
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let total = Int(t)
        let m = total / 60
        let s = total % 60
        let ms = Int((t - Double(total)) * 100)
        return String(format: "%d:%02d.%02d", m, s, ms)
    }

    private func sharpnessColor(_ sharpness: Double) -> Color {
        let s = max(0, min(1, sharpness))
        let r = 0.24 + (1.00 - 0.24) * s
        let g = 0.85 + (0.30 - 0.85) * s
        let b = 1.00 + (0.62 - 1.00) * s
        return Color(red: r, green: g, blue: b)
    }
}
