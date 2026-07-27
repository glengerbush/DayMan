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

                Image(systemName: moonPhaseSymbol)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        Color(hex: "#f2f7fc"),
                        Color(hex: snapshot.palette.background)
                    )
                    .font(.system(size: max(12, side * 0.05), weight: .regular))
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

    private var moonPhaseSymbol: String {
        let angle = snapshot.moon.phaseAngle
            .truncatingRemainder(dividingBy: 360)
        switch angle < 0 ? angle + 360 : angle {
        case 0 ..< 22.5, 337.5 ..< 360: "moonphase.new.moon"
        case 22.5 ..< 67.5: "moonphase.waxing.crescent"
        case 67.5 ..< 112.5: "moonphase.first.quarter"
        case 112.5 ..< 157.5: "moonphase.waxing.gibbous"
        case 157.5 ..< 202.5: "moonphase.full.moon"
        case 202.5 ..< 247.5: "moonphase.waning.gibbous"
        case 247.5 ..< 292.5: "moonphase.last.quarter"
        default: "moonphase.waning.crescent"
        }
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
