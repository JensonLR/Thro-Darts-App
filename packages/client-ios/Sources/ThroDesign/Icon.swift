import SwiftUI
import Foundation

/// Lucide (MIT) is the approved THRØ glyph set. Glyphs are inlined as path data, verbatim from
/// `docs/design/extracted/components/core/icons.js`, so they render offline and inherit a token
/// colour — the same two reasons the design inlines them. 24×24 grid, 2px stroke, round caps and
/// joins; the stroke scales with the rendered size exactly as an SVG's would.
///
/// SF Symbols would be the easy substitute and would be a substitution: a different glyph set with
/// different weights and optical sizes. The design names Lucide, so this draws Lucide.
public enum ThroIcon: String, CaseIterable, Sendable {
    case wifiOff = "wifi-off"
    case cloudCheck = "cloud-check"
    case clock
    case cloudOff = "cloud-off"
    case undo2 = "undo-2"
    case chevronLeft = "chevron-left"
    case chevronRight = "chevron-right"
    case circleCheck = "circle-check"
    case filePen = "file-pen"
    case smartphone
    case triangleAlert = "triangle-alert"
    case info
    case x
    case check
    case users
    case plus
    case play
    case rotateCcw = "rotate-ccw"
    case circle
    case ellipsis
    case pencilLine = "pencil-line"
    case house
    case target
    case radio
    case compass
    case circleUser = "circle-user"
    case bell
    case loader
    case minus
    case refreshCw = "refresh-cw"
    case trophy
    case user
    case circleAlert = "circle-alert"

    /// The inner SVG markup, verbatim from the export.
    var markup: String {
        switch self {
        case .wifiOff: return #"<path d="M12 20h.01"></path><path d="M8.5 16.429a5 5 0 0 1 7 0"></path><path d="M5 12.859a10 10 0 0 1 5.17-2.69"></path><path d="M19 12.859a10 10 0 0 0-2.007-1.523"></path><path d="M2 8.82a15 15 0 0 1 4.177-2.643"></path><path d="M22 8.82a15 15 0 0 0-11.288-3.764"></path><path d="m2 2 20 20"></path>"#
        case .cloudCheck: return #"<path d="m17 15-5.5 5.5L9 18"></path><path d="M5.516 16.07A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 3.501 7.327"></path>"#
        case .clock: return #"<circle cx="12" cy="12" r="10"></circle><path d="M12 6v6l4 2"></path>"#
        case .cloudOff: return #"<path d="M10.94 5.274A7 7 0 0 1 15.71 10h1.79a4.5 4.5 0 0 1 4.222 6.057"></path><path d="M18.796 18.81A4.5 4.5 0 0 1 17.5 19H9A7 7 0 0 1 5.79 5.78"></path><path d="m2 2 20 20"></path>"#
        case .undo2: return #"<path d="M9 14 4 9l5-5"></path><path d="M4 9h10.5a5.5 5.5 0 0 1 5.5 5.5a5.5 5.5 0 0 1-5.5 5.5H11"></path>"#
        case .chevronLeft: return #"<path d="m15 18-6-6 6-6"></path>"#
        case .chevronRight: return #"<path d="m9 18 6-6-6-6"></path>"#
        case .circleCheck: return #"<circle cx="12" cy="12" r="10"></circle><path d="m16 9-5.5 5.5L8 12"></path>"#
        case .filePen: return #"<path d="M12.659 22H18a2 2 0 0 0 2-2V8a2.4 2.4 0 0 0-.706-1.706l-3.588-3.588A2.4 2.4 0 0 0 14 2H6a2 2 0 0 0-2 2v9.34"></path><path d="M14 2v5a1 1 0 0 0 1 1h5"></path><path d="M10.378 12.622a1 1 0 0 1 3 3.003L8.36 20.637a2 2 0 0 1-.854.506l-2.867.837a.5.5 0 0 1-.62-.62l.836-2.869a2 2 0 0 1 .506-.853z"></path>"#
        case .smartphone: return #"<rect width="14" height="20" x="5" y="2" rx="2" ry="2"></rect><path d="M12 18h.01"></path>"#
        case .triangleAlert: return #"<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"></path><path d="M12 9v4"></path><path d="M12 17h.01"></path>"#
        case .info: return #"<circle cx="12" cy="12" r="10"></circle><path d="M12 16v-4"></path><path d="M12 8h.01"></path>"#
        case .x: return #"<path d="M18 6 6 18"></path><path d="m6 6 12 12"></path>"#
        case .check: return #"<path d="M20 6 9 17l-5-5"></path>"#
        case .users: return #"<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"></path><path d="M16 3.128a4 4 0 0 1 0 7.744"></path><path d="M22 21v-2a4 4 0 0 0-3-3.87"></path><circle cx="9" cy="7" r="4"></circle>"#
        case .plus: return #"<path d="M5 12h14"></path><path d="M12 5v14"></path>"#
        case .play: return #"<path d="M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"></path>"#
        case .rotateCcw: return #"<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"></path><path d="M3 3v5h5"></path>"#
        case .circle: return #"<circle cx="12" cy="12" r="10"></circle>"#
        case .ellipsis: return #"<circle cx="12" cy="12" r="1"></circle><circle cx="19" cy="12" r="1"></circle><circle cx="5" cy="12" r="1"></circle>"#
        case .pencilLine: return #"<path d="M13 21h8"></path><path d="m15 5 4 4"></path><path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"></path>"#
        case .house: return #"<path d="M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8"></path><path d="M3 10a2 2 0 0 1 .709-1.528l7-6a2 2 0 0 1 2.582 0l7 6A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path>"#
        case .target: return #"<circle cx="12" cy="12" r="10"></circle><circle cx="12" cy="12" r="6"></circle><circle cx="12" cy="12" r="2"></circle>"#
        case .radio: return #"<path d="M16.247 7.761a6 6 0 0 1 0 8.478"></path><path d="M19.075 4.933a10 10 0 0 1 0 14.134"></path><path d="M4.925 19.067a10 10 0 0 1 0-14.134"></path><path d="M7.753 16.239a6 6 0 0 1 0-8.478"></path><circle cx="12" cy="12" r="2"></circle>"#
        case .compass: return #"<circle cx="12" cy="12" r="10"></circle><path d="m16.24 7.76-1.804 5.411a2 2 0 0 1-1.265 1.265L7.76 16.24l1.804-5.411a2 2 0 0 1 1.265-1.265z"></path>"#
        case .circleUser: return #"<circle cx="12" cy="12" r="10"></circle><circle cx="12" cy="10" r="3"></circle><path d="M7 20.662V19a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v1.662"></path>"#
        case .bell: return #"<path d="M10.268 21a2 2 0 0 0 3.464 0"></path><path d="M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326"></path>"#
        case .loader: return #"<path d="M12 2v4"></path><path d="m16.2 7.8 2.9-2.9"></path><path d="M18 12h4"></path><path d="m16.2 16.2 2.9 2.9"></path><path d="M12 18v4"></path><path d="m4.9 19.1 2.9-2.9"></path><path d="M2 12h4"></path><path d="m4.9 4.9 2.9 2.9"></path>"#
        case .minus: return #"<path d="M5 12h14"></path>"#
        case .refreshCw: return #"<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"></path><path d="M21 3v5h-5"></path><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"></path><path d="M8 16H3v5"></path>"#
        case .trophy: return #"<path d="M10 14.66V17a1 1 0 0 1-1 1 2 2 0 0 0-2 2v2"></path><path d="M14 14.66V17a1 1 0 0 0 1 1 2 2 0 0 1 2 2v2"></path><path d="M17.916 10H19.5A2.5 2.5 0 0 0 22 7.5V5a1 1 0 0 0-1-1h-3"></path><path d="M4 22h16"></path><path d="M6 9a6 6 0 0 0 12 0V3a1 1 0 0 0-1-1H7a1 1 0 0 0-1 1z"></path><path d="M6.084 10H4.5A2.5 2.5 0 0 1 2 7.5V5a1 1 0 0 1 1-1h3"></path>"#
        case .user: return #"<path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"></path><circle cx="12" cy="7" r="4"></circle>"#
        // Lucide draws circle-alert with two <line> elements; these paths are the same strokes.
        case .circleAlert: return #"<circle cx="12" cy="12" r="10"></circle><path d="M12 8v4"></path><path d="M12 16h.01"></path>"#
        }
    }
}

/// Draws a Lucide glyph at `size` points, stroked in the current foreground style.
public struct Icon: View {
    private let icon: ThroIcon
    private let size: CGFloat

    public init(_ icon: ThroIcon, size: CGFloat = 20) {
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        IconShape(icon: icon)
            .stroke(style: StrokeStyle(lineWidth: 2 * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct IconShape: Shape {
    let icon: ThroIcon

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale)
        return LucideMarkup.path(icon.markup).applying(transform)
    }
}

/// Turns the export's inner SVG markup — `<path>`, `<circle>`, `<rect>` — into one `Path` in the
/// 24×24 grid.
enum LucideMarkup {

    static func path(_ markup: String) -> Path {
        var path = Path()
        for element in elements(in: markup) {
            switch element.name {
            case "path":
                if let d = element.attributes["d"] { path.addPath(SVGPathData.path(d)) }
            case "circle":
                let cx = element.number("cx"), cy = element.number("cy"), r = element.number("r")
                path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
            case "rect":
                let rect = CGRect(x: element.number("x"), y: element.number("y"),
                                  width: element.number("width"), height: element.number("height"))
                let rx = element.number("rx")
                let ry = element.attributes["ry"].flatMap { Double($0) }.map { CGFloat($0) } ?? rx
                if rx > 0 || ry > 0 {
                    path.addRoundedRect(in: rect, cornerSize: CGSize(width: rx, height: ry))
                } else {
                    path.addRect(rect)
                }
            default:
                break
            }
        }
        return path
    }

    struct Element {
        let name: String
        let attributes: [String: String]
        func number(_ key: String) -> CGFloat { CGFloat(Double(attributes[key] ?? "") ?? 0) }
    }

    static func elements(in markup: String) -> [Element] {
        let tag = try! NSRegularExpression(pattern: #"<(path|circle|rect)\b([^>]*)>"#)
        let attr = try! NSRegularExpression(pattern: #"([A-Za-z-]+)="([^"]*)""#)
        let ns = markup as NSString
        return tag.matches(in: markup, range: NSRange(location: 0, length: ns.length)).map { m in
            let name = ns.substring(with: m.range(at: 1))
            let body = ns.substring(with: m.range(at: 2)) as NSString
            var attributes: [String: String] = [:]
            for a in attr.matches(in: body as String, range: NSRange(location: 0, length: body.length)) {
                attributes[body.substring(with: a.range(at: 1))] = body.substring(with: a.range(at: 2))
            }
            return Element(name: name, attributes: attributes)
        }
    }
}

/// SVG path data → `Path`. Supports M L H V C S Q T A Z in absolute and relative forms, implicit
/// repeated coordinates, and SVG's compact number syntax (`5-5`, `.5.5`).
enum SVGPathData {

    static func path(_ d: String) -> Path {
        var path = Path()
        var tokens = tokenize(d)[...]
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint? = nil   // for S/T reflection
        var lastCommand: Character = " "

        func number() -> CGFloat? {
            guard let t = tokens.first, case .number(let v) = t else { return nil }
            tokens.removeFirst()
            return v
        }
        func point(relative: Bool) -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while let t = tokens.first {
            let command: Character
            if case .command(let c) = t {
                tokens.removeFirst()
                command = c
            } else {
                // Implicit repetition: numbers after M behave as L, otherwise repeat the last command.
                command = (lastCommand == "M") ? "L" : (lastCommand == "m") ? "l" : lastCommand
                if command == " " { break }
            }
            let relative = command.isLowercase
            switch command.uppercased() {
            case "M":
                guard let p = point(relative: relative) else { return path }
                path.move(to: p); current = p; start = p; lastControl = nil
            case "L":
                guard let p = point(relative: relative) else { return path }
                path.addLine(to: p); current = p; lastControl = nil
            case "H":
                guard let x = number() else { return path }
                let p = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: p); current = p; lastControl = nil
            case "V":
                guard let y = number() else { return path }
                let p = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: p); current = p; lastControl = nil
            case "C":
                guard let c1 = point(relative: relative), let c2 = point(relative: relative),
                      let p = point(relative: relative) else { return path }
                path.addCurve(to: p, control1: c1, control2: c2); lastControl = c2; current = p
            case "S":
                guard let c2 = point(relative: relative), let p = point(relative: relative) else { return path }
                let c1 = reflect(lastControl, about: current, ifPreviousWasCubic: "CS".contains(lastCommand.uppercased()))
                path.addCurve(to: p, control1: c1, control2: c2); lastControl = c2; current = p
            case "Q":
                guard let c = point(relative: relative), let p = point(relative: relative) else { return path }
                path.addQuadCurve(to: p, control: c); lastControl = c; current = p
            case "T":
                guard let p = point(relative: relative) else { return path }
                let c = reflect(lastControl, about: current, ifPreviousWasCubic: "QT".contains(lastCommand.uppercased()))
                path.addQuadCurve(to: p, control: c); lastControl = c; current = p
            case "A":
                guard let rx = number(), let ry = number(), let rot = number(),
                      let large = number(), let sweep = number(), let p = point(relative: relative) else { return path }
                arc(&path, from: current, to: p, rx: rx, ry: ry, rotationDegrees: rot,
                    largeArc: large != 0, sweep: sweep != 0)
                current = p; lastControl = nil
            case "Z":
                path.closeSubpath(); current = start; lastControl = nil
            default:
                return path
            }
            lastCommand = command
        }
        return path
    }

    private static func reflect(_ control: CGPoint?, about current: CGPoint, ifPreviousWasCubic ok: Bool) -> CGPoint {
        guard ok, let c = control else { return current }
        return CGPoint(x: 2 * current.x - c.x, y: 2 * current.y - c.y)
    }

    /// SVG endpoint arc → centre parameterisation (SVG 1.1 §F.6.5) → cubic segments of at most 90°.
    private static func arc(_ path: inout Path, from p1: CGPoint, to p2: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                            rotationDegrees: CGFloat, largeArc: Bool, sweep: Bool) {
        if p1 == p2 { return }
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 { path.addLine(to: p2); return }

        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p1.x - p2.x) / 2, dy = (p1.y - p2.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { let s = sqrt(lambda); rx *= s; ry *= s }

        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = den == 0 ? 0 : sign * sqrt(max(0, num / den))
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * (-ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(max(-1, min(1, len == 0 ? 1 : dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        func pointAt(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi,
                    y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func derivativeAt(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi,
                    y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }
        var a = theta1
        for _ in 0..<segments {
            let b = a + step
            let k = 4.0 / 3.0 * tan((b - a) / 4)
            let start = pointAt(a), end = pointAt(b)
            let d0 = derivativeAt(a), d1 = derivativeAt(b)
            path.addCurve(to: end,
                          control1: CGPoint(x: start.x + k * d0.x, y: start.y + k * d0.y),
                          control2: CGPoint(x: end.x - k * d1.x, y: end.y - k * d1.y))
            a = b
        }
    }

    enum Token { case command(Character), number(CGFloat) }

    static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var sawDot = false, sawExponent = false

        func flush() {
            if !current.isEmpty, let v = Double(current) { tokens.append(.number(CGFloat(v))) }
            current = ""; sawDot = false; sawExponent = false
        }

        for ch in d {
            if ch.isLetter && !((ch == "e" || ch == "E") && !current.isEmpty) {
                flush(); tokens.append(.command(ch))
            } else if ch == "," || ch.isWhitespace {
                flush()
            } else if ch == "-" || ch == "+" {
                let afterExponent = current.last.map { $0 == "e" || $0 == "E" } ?? false
                if !current.isEmpty && !afterExponent { flush() }
                current.append(ch)
            } else if ch == "." {
                if sawDot && !sawExponent { flush() }
                sawDot = true; current.append(ch)
            } else if ch == "e" || ch == "E" {
                sawExponent = true; current.append(ch)
            } else if ch.isNumber {
                current.append(ch)
            }
        }
        flush()
        return tokens
    }
}
