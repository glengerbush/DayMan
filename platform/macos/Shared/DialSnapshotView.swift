import SwiftUI

struct DialSnapshotView: View {
    let snapshot: ClockSnapshot
    let date: Date

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let scale = side / CGFloat(snapshot.geometry.viewBox)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: snapshot.palette.face),
                                Color(hex: snapshot.palette.background)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: side * 0.52
                        )
                    )

                ForEach(snapshot.arcs) { arc in
                    Circle()
                        .stroke(
                            Color(hex: snapshot.palette.track).opacity(0.75),
                            lineWidth: CGFloat(arc.strokeWidth) * scale
                        )
                        .frame(
                            width: CGFloat(arc.radius * 2) * scale,
                            height: CGFloat(arc.radius * 2) * scale
                        )

                    ForEach(Array(arc.ranges.enumerated()), id: \.offset) { _, range in
                        MinuteArcShape(range: range)
                            .stroke(
                                Color(hex: arc.color),
                                style: StrokeStyle(
                                    lineWidth: CGFloat(arc.strokeWidth) * scale,
                                    lineCap: .butt
                                )
                            )
                            .frame(
                                width: CGFloat(arc.radius * 2) * scale,
                                height: CGFloat(arc.radius * 2) * scale
                            )
                    }
                }

                ForEach(snapshot.hourLabels) { label in
                    Text(label.label)
                        .font(
                            .system(
                                size: max(7, side * 0.035),
                                weight: .medium,
                                design: .rounded
                            )
                            .monospacedDigit()
                        )
                        .foregroundStyle(Color(hex: snapshot.palette.mutedText))
                        .position(
                            point(
                                minute: label.minute,
                                radius: CGFloat(snapshot.geometry.hourLabelRadius) * scale,
                                side: side
                            )
                        )
                }

                ForEach(snapshot.events.filter(\.visibleOnDial)) { event in
                    Circle()
                        .fill(event.body == .sun ? Color(hex: "#ffb552") : Color.white)
                        .frame(width: 6, height: 6)
                        .position(
                            point(
                                minute: event.minute,
                                radius: CGFloat(event.radius) * scale,
                                side: side
                            )
                        )
                }

                MoonPhaseGlyph(
                    illumination: snapshot.moon.illumination,
                    waxing: normalizedMoonPhaseAngle <= 180,
                    lightColor: Color(hex: "#d9e5ea"),
                    darkColor: Color(hex: "#050b14"),
                    outlineColor: Color(hex: "#8fa0a8")
                )
                    .frame(
                        width: max(14, side * 0.055),
                        height: max(14, side * 0.055)
                    )
                    .position(
                        point(
                            minute: snapshot.moon.markerMinute,
                            radius: CGFloat(snapshot.geometry.moonRadius) * scale,
                            side: side
                        )
                    )

                currentTimeHand(side: side, scale: scale)

                VStack(spacing: 2) {
                    Text(timeText)
                        .font(
                            .system(
                                size: side * 0.105,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()
                    Text(snapshot.location.label)
                        .font(
                            .system(
                                size: side * 0.04,
                                weight: .medium,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(Color(hex: snapshot.palette.mutedText))
                        .lineLimit(1)
                }
                .foregroundStyle(Color(hex: snapshot.palette.text))
                .padding(side * 0.22)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.accessibilityText)
    }

    private func currentTimeHand(side: CGFloat, scale: CGFloat) -> some View {
        let start = point(
            minute: currentMinute,
            radius: CGFloat(snapshot.geometry.handStartRadius) * scale,
            side: side
        )
        let end = point(
            minute: currentMinute,
            radius: CGFloat(snapshot.geometry.handEndRadius) * scale,
            side: side
        )
        return Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(
            Color(hex: snapshot.palette.currentHand).opacity(0.9),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 4])
        )
    }

    private func point(minute: Double, radius: CGFloat, side: CGFloat) -> CGPoint {
        let angle = minute / 1_440 * 2 * Double.pi
        return CGPoint(
            x: side / 2 + CGFloat(sin(angle)) * radius,
            y: side / 2 - CGFloat(cos(angle)) * radius
        )
    }

    private var configuredTimeZone: TimeZone {
        TimeZone(identifier: snapshot.timezone) ?? .current
    }

    private var currentMinute: Double {
        let components = Calendar.current.dateComponents(
            in: configuredTimeZone,
            from: date
        )
        return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.timeZone = configuredTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var normalizedMoonPhaseAngle: Double {
        let angle = snapshot.moon.phaseAngle
            .truncatingRemainder(dividingBy: 360)
        return angle < 0 ? angle + 360 : angle
    }
}

/// A compact Moon marker whose lit area continuously follows the snapshot's
/// illumination instead of rounding to one of the eight system phase symbols.
private struct MoonPhaseGlyph: View {
    let illumination: Double
    let waxing: Bool
    let lightColor: Color
    let darkColor: Color
    let outlineColor: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(darkColor)

            MoonIlluminationShape(
                illumination: illumination,
                waxing: waxing
            )
            .fill(lightColor)

            Circle()
                .stroke(outlineColor, lineWidth: 0.8)
        }
    }
}

/// Projects the day/night terminator onto the lunar disc. At 94%
/// illumination the remaining 6% shadow stays visible rather than being
/// rounded to a full-Moon icon.
private struct MoonIlluminationShape: Shape {
    let illumination: Double
    let waxing: Bool

    func path(in rect: CGRect) -> Path {
        let litFraction = min(max(illumination, 0), 1)
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let terminator = CGFloat(1 - 2 * litFraction)
        let sampleCount = 64
        var path = Path()

        for step in 0 ... sampleCount {
            let y = -radius + 2 * radius * CGFloat(step) / CGFloat(sampleCount)
            let extent = sqrt(max(0, radius * radius - y * y))
            let x = waxing ? extent : -terminator * extent
            let point = CGPoint(x: center.x + x, y: center.y + y)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        for step in stride(from: sampleCount, through: 0, by: -1) {
            let y = -radius + 2 * radius * CGFloat(step) / CGFloat(sampleCount)
            let extent = sqrt(max(0, radius * radius - y * y))
            let x = waxing ? terminator * extent : -extent
            path.addLine(to: CGPoint(x: center.x + x, y: center.y + y))
        }

        path.closeSubpath()
        return path
    }
}

private struct MinuteArcShape: Shape {
    let range: MinuteRange

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(range.startMinute / 4 - 90),
            endAngle: .degrees(range.endMinute / 4 - 90),
            clockwise: false
        )
        return path
    }
}

private extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)
        let red, green, blue, alpha: UInt64
        switch sanitized.count {
        case 8:
            red = value >> 24
            green = value >> 16 & 0xff
            blue = value >> 8 & 0xff
            alpha = value & 0xff
        default:
            red = value >> 16
            green = value >> 8 & 0xff
            blue = value & 0xff
            alpha = 0xff
        }
        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }
}
