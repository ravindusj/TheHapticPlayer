import ActivityKit
import WidgetKit
import SwiftUI

private let hapticAccent: Color = Color(white: 0.78)
private let progressTrackColor: Color = Color(white: 0.32)
private let completionGreen: Color = Color(red: 0.20, green: 0.85, blue: 0.40)

private func isCompleted(_ state: HapticProcessingAttributes.ContentState) -> Bool {
    state.statusRaw == "completed" || state.progress >= 0.999
}

struct HapticActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HapticProcessingAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let done = isCompleted(context.state)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StatusIcon(size: 22, isCompleted: done)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(done ? completionGreen : .white)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: context.state.progress)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.attributes.videoName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        ProgressView(value: context.state.progress)
                            .progressViewStyle(.linear)
                            .tint(done ? completionGreen : hapticAccent)
                            .animation(.easeInOut(duration: 0.3), value: context.state.progress)
                        Text(context.state.statusLabel)
                            .font(.caption2)
                            .foregroundStyle((done ? completionGreen : Color.white).opacity(done ? 0.95 : 0.65))
                            .lineLimit(1)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.3), value: context.state.statusLabel)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
                }
            } compactLeading: {
                StatusIcon(size: 14, isCompleted: done)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(done ? completionGreen : .white)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: context.state.progress)
            } minimal: {
                ZStack {
                    Circle()
                        .stroke(progressTrackColor, lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(0.02, context.state.progress))
                        .stroke(
                            done ? completionGreen : hapticAccent,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: context.state.progress)
                    Image(systemName: done ? "checkmark" : "bolt.horizontal.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(done ? completionGreen : hapticAccent)
                        .transition(.scale.combined(with: .opacity))
                        .id(done)
                }
            }
            .keylineTint(done ? completionGreen : hapticAccent)
        }
    }
}

private struct StatusIcon: View {
    let size: CGFloat
    let isCompleted: Bool

    @State private var pulsing = false
    @State private var checkScale: CGFloat = 0.4
    @State private var checkOpacity: Double = 0

    var body: some View {
        ZStack {
            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(completionGreen)
                    .scaleEffect(checkScale)
                    .opacity(checkOpacity)
                    .onAppear {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                            checkScale = 1.0
                            checkOpacity = 1.0
                        }
                    }
            } else {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(hapticAccent)
                    .opacity(pulsing ? 1.0 : 0.55)
                    .scaleEffect(pulsing ? 1.0 : 0.88)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: pulsing
                    )
                    .onAppear { pulsing = true }
            }
        }
        .transition(.scale.combined(with: .opacity))
        .animation(.easeInOut(duration: 0.35), value: isCompleted)
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<HapticProcessingAttributes>

    private var done: Bool { isCompleted(context.state) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                StatusIcon(size: 22, isCompleted: done)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TheHapticPlayer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(context.attributes.videoName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer()
                Text("\(Int(context.state.progress * 100))%")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(done ? completionGreen : .white)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: context.state.progress)
            }

            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: context.state.progress)
                    .progressViewStyle(.linear)
                    .tint(done ? completionGreen : hapticAccent)
                    .animation(.easeInOut(duration: 0.3), value: context.state.progress)
                Text(context.state.statusLabel)
                    .font(.caption2)
                    .foregroundStyle((done ? completionGreen : Color.white).opacity(done ? 0.95 : 0.6))
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: context.state.statusLabel)
            }
        }
        .padding(16)
    }
}
