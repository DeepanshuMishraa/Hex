import Inject
import SwiftUI

// MARK: - Transcription Indicator (Notch)
//
// A small, minimal indicator that lives inside the macOS notch (the
// hardware camera housing at the top-center of the screen). It shows a
// 4-bar waveform that responds to the audio meter, and a small pulse
// dot for idle states. The container has a black fill to blend seamlessly
// with the notch's own black housing — so it looks like the waveform is
// drawn on the notch itself.
//
// Behaviour matrix:
//   .hidden        — invisible
//   .optionKeyPressed / .prewarming — small idle pulse, no waveform
//   .recording      — 4 bars reacting to the live audio meter
//   .transcribing   — 4 bars on a slow animated sine wave

// MARK: - Notch Geometry

private struct NotchGeometry: Equatable {
  var hasNotch: Bool
  var notchWidth: CGFloat
  var notchHeight: CGFloat
  var menuBarHeight: CGFloat
}

@MainActor
private func getNotchGeometry() -> NotchGeometry {
  let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
    ?? NSScreen.main
    ?? NSScreen.screens[0]
  
  if #available(macOS 12.0, *),
     let topLeft = screen.auxiliaryTopLeftArea,
     let topRight = screen.auxiliaryTopRightArea {
    let width = topRight.origin.x - (topLeft.origin.x + topLeft.size.width)
    let height = max(topLeft.size.height, topRight.size.height)
    let notchHeight = max(height, 32)
    let menuBarHeight = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 24
    return NotchGeometry(
      hasNotch: true,
      notchWidth: width,
      notchHeight: notchHeight,
      menuBarHeight: menuBarHeight
    )
  } else {
    // Non-notched screen fallback (simulate a notch)
    return NotchGeometry(
      hasNotch: false,
      notchWidth: 120,
      notchHeight: 32,
      menuBarHeight: 24
    )
  }
}

struct TranscriptionIndicatorView: View {
  @ObserveInjection var inject

  enum Status {
    case hidden
    case optionKeyPressed
    case recording
    case transcribing
    case prewarming
  }

  var status: Status
  var meter: Meter

  // MARK: - Sizing
  private let extensionWidth: CGFloat = 40
  private let maxBarHeight: CGFloat = 14
  private let minBarHeight: CGFloat = 3

  @State private var geometry = NotchGeometry(hasNotch: false, notchWidth: 120, notchHeight: 32, menuBarHeight: 24)

  var body: some View {
    ZStack(alignment: .top) {
      if isActive {
        // Black housing that blends with the notch's own black bezel.
        // Only shown when the indicator is active.
        UnevenRoundedRectangle(
          topLeadingRadius: 0,
          bottomLeadingRadius: 10,
          bottomTrailingRadius: 10,
          topTrailingRadius: 0
        )
        .fill(Color.black)
        .frame(width: geometry.notchWidth + extensionWidth * 2, height: geometry.notchHeight)
        .transition(.move(edge: .top).combined(with: .opacity))
      }

      // Content — aligned to the left of the notch (in the left extension)
      if isActive {
        HStack(spacing: 0) {
          Group {
            switch status {
            case .hidden:
              EmptyView()
            case .optionKeyPressed, .prewarming:
              IdleDot(color: .white.opacity(0.6))
            case .recording:
              NotchWaveform(meter: meter, color: .white)
            case .transcribing:
              NotchWaveform(meter: meter, color: .white, isTranscribing: true)
            }
          }
          .frame(width: extensionWidth, alignment: .center)
          
          Spacer() // Covers the notch width + right extension
        }
        .frame(width: geometry.notchWidth + extensionWidth * 2, height: geometry.notchHeight)
      }
    }
    .frame(width: geometry.notchWidth + extensionWidth * 2, height: geometry.notchHeight)
    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: status)
    .onAppear {
      updateGeometry()
    }
    .onChange(of: status) { _ in
      updateGeometry()
    }
    .enableInjection()
  }

  private var isActive: Bool {
    status != .hidden
  }

  private func updateGeometry() {
    geometry = getNotchGeometry()
  }
}

// MARK: - Idle Dot
//
// A single small dot for the optionKeyPressed / prewarming states.

struct IdleDot: View {
  let color: Color
  @State private var isPulsing = false

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 5, height: 5)
      .scaleEffect(isPulsing ? 1.0 : 0.7)
      .opacity(isPulsing ? 1.0 : 0.4)
      .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
      .onAppear { isPulsing = true }
  }
}

// MARK: - Notch Waveform
//
// Four small white bars that react to the live audio meter in real time.
// When audio is loud, the bars grow; when quiet, they shrink. A fast
// attack / slow release on each bar gives it the feel of a real audio
// meter rather than a flat/static display.

struct NotchWaveform: View {
  let meter: Meter
  let color: Color
  var isTranscribing: Bool = false

  private let barCount = 4
  private let barWidth: CGFloat = 2.5
  private let barSpacing: CGFloat = 4
  private let maxBarHeight: CGFloat = 14
  private let minBarHeight: CGFloat = 3
  @State private var smoothedLevels: [Double] = []
  @State private var phase: Double = 0

  private let timer = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()

  var body: some View {
    HStack(spacing: barSpacing) {
      ForEach(0..<barCount, id: \.self) { index in
        Capsule()
          .fill(color)
          .frame(width: barWidth, height: barHeight(for: index))
      }
    }
    .onAppear { ensureLevels() }
    .onChange(of: meter) { newMeter in
      if !isTranscribing {
        updateLevels(for: newMeter)
      }
    }
    .onReceive(timer) { _ in
      if isTranscribing {
        phase += 0.15
      }
    }
    .animation(.linear(duration: 0.05), value: smoothedLevels)
    .animation(.linear(duration: 0.05), value: phase)
  }

  private func ensureLevels() {
    if smoothedLevels.count != barCount {
      smoothedLevels = Array(repeating: 0, count: barCount)
    }
  }

  private func updateLevels(for newMeter: Meter) {
    ensureLevels()
    let average = min(1.0, newMeter.averagePower * 3.0)
    let peak = min(1.0, newMeter.peakPower * 3.0)

    var newLevels = smoothedLevels
    for i in 0..<barCount {
      // Each bar reacts to a different frequency band — center bars are
      // more sensitive, edge bars are slightly attenuated. This gives the
      // wave a "shape" rather than every bar moving in lockstep.
      let position = Double(i) / Double(barCount - 1) // 0...1
      let bandCenter = 0.5 - abs(position - 0.5) * 0.6 // 0.5...0.2...0.5
      let sensitivity = 0.4 + bandCenter * 0.6
      let target = average * sensitivity
      let peakBoost = peak > target + 0.1 ? (peak - target) * 0.6 : 0
      let newValue = max(target, peakBoost)

      // Fast attack, slow release
      let prev = newLevels[i]
      let smoothed = newValue > prev
        ? min(newValue, prev + 0.5)   // attack: jump up fast
        : max(newValue, prev * 0.78)  // release: fall slowly
      newLevels[i] = smoothed
    }
    smoothedLevels = newLevels
  }

  private func barHeight(for index: Int) -> CGFloat {
    if isTranscribing {
      let offset = Double(index) * 0.5
      let val = sin(phase + offset) * 0.5 + 0.5
      return minBarHeight + val * (maxBarHeight - minBarHeight)
    } else {
      let level = index < smoothedLevels.count ? smoothedLevels[index] : 0
      let t = CGFloat(level)
      return minBarHeight + t * (maxBarHeight - minBarHeight)
    }
  }
}

#Preview {
  VStack(spacing: 24) {
    TranscriptionIndicatorView(
      status: .optionKeyPressed,
      meter: Meter(averagePower: 0, peakPower: 0)
    )
    TranscriptionIndicatorView(
      status: .recording,
      meter: Meter(averagePower: 0.5, peakPower: 0.7)
    )
    TranscriptionIndicatorView(
      status: .transcribing,
      meter: Meter(averagePower: 0.2, peakPower: 0.3)
    )
  }
  .padding(40)
  .background(Color.gray)
}
