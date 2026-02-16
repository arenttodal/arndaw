import SwiftUI

// MARK: - Waveform Preview View

/// Renders a waveform from an array of peak amplitude samples
/// Used in the seed library for visual audio previews
public struct WaveformPreviewView: View {
    let samples: [Float]
    var color: Color = .accentColor

    public init(samples: [Float], color: Color = .accentColor) {
        self.samples = samples
        self.color = color
    }

    public var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard !samples.isEmpty else { return }

                let barWidth = size.width / CGFloat(samples.count)
                let midY = size.height / 2

                for (index, sample) in samples.enumerated() {
                    let amplitude = CGFloat(min(abs(sample), 1.0))
                    let barHeight = max(amplitude * size.height * 0.9, 1)
                    let x = CGFloat(index) * barWidth

                    let rect = CGRect(
                        x: x,
                        y: midY - barHeight / 2,
                        width: max(barWidth - 0.5, 0.5),
                        height: barHeight
                    )

                    // Color gradient based on amplitude
                    let opacity = 0.3 + Double(amplitude) * 0.7
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth > 2 ? 1 : 0),
                        with: .color(color.opacity(opacity))
                    )
                }
            }
        }
    }
}
