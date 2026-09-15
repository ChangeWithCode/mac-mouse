import GlideCore
import SwiftUI

/// A direct-manipulation editor for the acceleration curve.
///
/// The curve decides how wheel cadence becomes scroll distance, and it is the
/// difference between a mouse that feels precise and one that feels twitchy.
/// Exposing it as two numeric fields would be technically complete and
/// practically useless, so the control points are dragged and the effect is
/// shown as it happens: the axes are labelled in the units the user actually
/// experiences — notches per second in, points per notch out — rather than in
/// abstract 0–1 Bézier space.
struct CurveEditor: View {

    @Binding var curve: AccelerationCurve
    /// Live input cadence from the engine, drawn as a moving marker so the curve
    /// can be tuned against real scrolling rather than guesswork.
    var liveCadence: Double = 0

    @State private var dragging: Handle?

    private enum Handle { case first, second }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            GeometryReader { geometry in
                let plot = plotRect(in: geometry.size)
                ZStack {
                    grid(in: plot)
                    filledCurve(in: plot)
                    curvePath(in: plot)
                    liveMarker(in: plot)
                    handles(in: plot)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(in: plot))
            }
            .frame(height: 220)
            .background(Design.Palette.surface, in: RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
                    .strokeBorder(Design.Palette.separator.opacity(0.6), lineWidth: 1)
            )

            axisLabels
        }
    }

    // MARK: - Geometry

    private func plotRect(in size: CGSize) -> CGRect {
        CGRect(x: 18, y: 14, width: max(size.width - 36, 1), height: max(size.height - 40, 1))
    }

    /// Bézier space (0–1, y up) to view space (points, y down).
    private func point(_ x: Double, _ y: Double, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.maxY - y * rect.height)
    }

    private func normalised(_ location: CGPoint, in rect: CGRect) -> (x: Double, y: Double) {
        (
            min(max((location.x - rect.minX) / rect.width, 0), 1),
            min(max((rect.maxY - location.y) / rect.height, 0), 1)
        )
    }

    // MARK: - Layers

    private func grid(in rect: CGRect) -> some View {
        Path { path in
            for step in 0...4 {
                let fraction = Double(step) / 4.0
                let y = rect.maxY - fraction * rect.height
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
                let x = rect.minX + fraction * rect.width
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
        }
        .stroke(Design.Palette.separator.opacity(0.35), lineWidth: 1)
    }

    private func curveSamples(in rect: CGRect) -> [CGPoint] {
        // 80 samples is past the point where the eye can see the segments, and
        // cheap enough to recompute on every frame of a drag.
        (0...80).map { step in
            let x = Double(step) / 80.0
            return point(x, curve.shape.evaluate(x), in: rect)
        }
    }

    private func curvePath(in rect: CGRect) -> some View {
        Path { path in
            let samples = curveSamples(in: rect)
            guard let first = samples.first else { return }
            path.move(to: first)
            for sample in samples.dropFirst() { path.addLine(to: sample) }
        }
        .stroke(Design.Palette.accentGradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }

    private func filledCurve(in rect: CGRect) -> some View {
        Path { path in
            let samples = curveSamples(in: rect)
            guard let first = samples.first else { return }
            path.move(to: CGPoint(x: first.x, y: rect.maxY))
            path.addLine(to: first)
            for sample in samples.dropFirst() { path.addLine(to: sample) }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [Design.Palette.accent.opacity(0.22), Design.Palette.accent.opacity(0.02)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    @ViewBuilder
    private func liveMarker(in rect: CGRect) -> some View {
        if liveCadence > curve.minSpeed {
            let span = max(curve.maxSpeed - curve.minSpeed, 0.0001)
            let progress = min(max((liveCadence - curve.minSpeed) / span, 0), 1)
            let position = point(progress, curve.shape.evaluate(progress), in: rect)

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: position.x, y: rect.minY))
                    path.addLine(to: CGPoint(x: position.x, y: rect.maxY))
                }
                .stroke(Design.Palette.signal.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                Circle()
                    .fill(Design.Palette.signal)
                    .frame(width: 9, height: 9)
                    .position(position)
                    .shadow(color: Design.Palette.signal.opacity(0.6), radius: 5)
            }
            .animation(Design.Motion.subtle, value: liveCadence)
        }
    }

    private func handles(in rect: CGRect) -> some View {
        let first = point(curve.shape.x1, curve.shape.y1, in: rect)
        let second = point(curve.shape.x2, curve.shape.y2, in: rect)

        return ZStack {
            // Tethers back to the endpoints each handle governs, so it is
            // visible which end of the curve a handle is pulling on.
            Path { path in
                path.move(to: point(0, 0, in: rect)); path.addLine(to: first)
                path.move(to: point(1, 1, in: rect)); path.addLine(to: second)
            }
            .stroke(Design.Palette.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            handle(at: first, active: dragging == .first)
            handle(at: second, active: dragging == .second)
        }
    }

    private func handle(at position: CGPoint, active: Bool) -> some View {
        Circle()
            .fill(Design.Palette.elevated)
            .overlay(Circle().strokeBorder(Design.Palette.accent, lineWidth: active ? 3 : 2))
            .frame(width: active ? 17 : 14, height: active ? 17 : 14)
            .shadow(color: .black.opacity(0.18), radius: active ? 5 : 2, y: 1)
            .position(position)
            .animation(Design.Motion.subtle, value: active)
    }

    // MARK: - Interaction

    private func dragGesture(in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let handle = dragging ?? nearestHandle(to: value.startLocation, in: rect)
                dragging = handle
                let position = normalised(value.location, in: rect)

                // y is free to overshoot 0–1 (that is what gives a curve its
                // anticipation and overshoot); x is clamped because a
                // non-monotonic x would make the curve impossible to invert.
                let shape = curve.shape
                curve.shape = handle == .first
                    ? UnitBezier(position.x, position.y, shape.x2, shape.y2)
                    : UnitBezier(shape.x1, shape.y1, position.x, position.y)
            }
            .onEnded { _ in dragging = nil }
    }

    private func nearestHandle(to location: CGPoint, in rect: CGRect) -> Handle {
        let first = point(curve.shape.x1, curve.shape.y1, in: rect)
        let second = point(curve.shape.x2, curve.shape.y2, in: rect)
        return hypot(location.x - first.x, location.y - first.y)
            <= hypot(location.x - second.x, location.y - second.y) ? .first : .second
    }

    // MARK: - Labels

    private var axisLabels: some View {
        HStack {
            Label("\(Int(curve.minDistance)) pt at \(Int(curve.minSpeed)) notch/s", systemImage: "tortoise")
            Spacer()
            Label("\(Int(curve.maxDistance)) pt at \(Int(curve.maxSpeed)) notch/s", systemImage: "hare")
        }
        .font(Design.Typography.caption)
        .foregroundStyle(Design.Palette.secondaryLabel)
    }
}
