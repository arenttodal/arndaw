import SwiftUI

// MARK: - Capture Timeline View

/// Visual representation of the rolling capture buffer
/// Shows a scrolling timeline of the buffer with the current position
public struct CaptureTimelineView: View {
    let bufferDuration: TimeInterval
    let maxDuration: TimeInterval
    let isCapturing: Bool

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                // Filled portion (how much buffer is used)
                let fillRatio = min(bufferDuration / maxDuration, 1.0)
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [Color.red.opacity(0.05), Color.red.opacity(0.15)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(fillRatio))

                // Time markers
                HStack {
                    ForEach(0..<6) { minute in
                        if minute > 0 {
                            Spacer()
                        }
                        VStack {
                            Spacer()
                            Text("-\(5 - minute)m")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(.bottom, 4)
                        if minute < 5 {
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 8)

                // Current position indicator (right edge of fill)
                if isCapturing {
                    let xPos = geometry.size.width * CGFloat(fillRatio)
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2, height: geometry.size.height - 8)
                        .position(x: xPos, y: geometry.size.height / 2)

                    // "NOW" label
                    Text("NOW")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                        .position(x: xPos, y: 8)
                }
            }
        }
    }
}
