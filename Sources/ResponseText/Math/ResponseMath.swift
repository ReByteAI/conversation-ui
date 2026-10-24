import Foundation

/// Math is recognized outside code. Currency, escaped delimiters and incomplete
/// streamed equations remain literal; a later snapshot can finish the equation.
public struct ResponseMath {
    public struct Equation { public let source: String; public let display: Bool; public let complete: Bool }
    public let protected: String
    public let renderedMarkdown: String
    public let equations: [String: Equation]

    public init(_ source: String) {
        let chars = Array(source)
        var output = "", rendered = "", equations: [String: Equation] = [:], i = 0
        var prefix = "RESPONSEMATHTOKEN"
        while source.contains(prefix) { prefix += "X" }
        var fence: (Character, Int)?
        func matches(_ value: String, _ offset: Int) -> Bool {
            let value = Array(value)
            return offset + value.count <= chars.count && chars[offset..<(offset + value.count)].elementsEqual(value)
        }
        func escaped(_ offset: Int) -> Bool {
            var cursor = offset, count = 0
            while cursor > 0 && chars[cursor - 1] == "\\" { count += 1; cursor -= 1 }
            return !count.isMultiple(of: 2)
        }
        while i < chars.count {
            // Preserve complete fence lines and their bodies, including incomplete fences.
            if i == 0 || chars[i - 1] == "\n" {
                let end = chars[i...].firstIndex(of: "\n") ?? chars.count
                let line = Array(chars[i..<end])
                let spaces = line.prefix(while: { $0 == " " }).count
                let trimmed = Array(line.dropFirst(spaces))
                let run = trimmed.first.map { first in trimmed.prefix(while: { $0 == first }).count } ?? 0
                if spaces <= 3, let first = trimmed.first, [Character("`"), Character("~")].contains(first), run >= 3 {
                    if let active = fence {
                        if first == active.0 && run >= active.1 && trimmed.dropFirst(run).allSatisfy(\.isWhitespace) { fence = nil }
                    } else { fence = (first, run) }
                    output += String(line); rendered += String(line); i = end
                    if i < chars.count { output.append(chars[i]); rendered.append(chars[i]); i += 1 }; continue
                }
                if fence != nil || spaces >= 4 {
                    output += String(line); rendered += String(line); i = end
                    if i < chars.count { output.append(chars[i]); rendered.append(chars[i]); i += 1 }; continue
                }
            }
            if chars[i] == "`", !escaped(i) {
                let count = chars[i...].prefix(while: { $0 == "`" }).count
                var end = i + count
                while end < chars.count {
                    if chars[end] == "`" {
                        let close = chars[end...].prefix(while: { $0 == "`" }).count
                        if close == count { end += count; break }
                        end += close
                    } else { end += 1 }
                }
                output += String(chars[i..<end]); rendered += String(chars[i..<end]); i = end; continue
            }
            let delimiters: [(String, String, Bool)] = [("\\[", "\\]", true), ("\\(", "\\)", false), ("$$", "$$", true), ("$", "$", false)]
            var consumed = false
            for (open, close, display) in delimiters where matches(open, i) && !escaped(i) {
                let content = i + open.count
                if content >= chars.count { continue }
                if open == "$", chars[content].isWhitespace || chars[content] == "$" { continue }
                var end = content
                while end < chars.count {
                    if !display && (chars[end] == "\n" || chars[end] == "`") { break }
                    if matches(close, end), !escaped(end) {
                        if end == content || (open == "$" && (chars[end - 1].isWhitespace || (end + 1 < chars.count && chars[end + 1].isNumber))) { break }
                        let token = "\(prefix)\(equations.count)END"
                        equations[token] = Equation(source: String(chars[i..<(end + close.count)]), display: display, complete: true)
                        rendered += (display ? "$$" : "$") + String(chars[content..<end]) + (display ? "$$" : "$")
                        output += token; i = end + close.count; consumed = true; break
                    }
                    end += 1
                }
                if !consumed && open != "$" {
                    let token = "\(prefix)\(equations.count)END"
                    equations[token] = Equation(source: String(chars[i..<end]), display: display, complete: false)
                    rendered += String(chars[i..<end]).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "$", with: "\\$")
                    output += token; i = end; consumed = true
                }
                if consumed { break }
            }
            if !consumed {
                if chars[i] == "$", !escaped(i) { rendered += "\\" }
                rendered.append(chars[i]); output.append(chars[i]); i += 1
            }
        }
        renderedMarkdown = rendered
        protected = output
        self.equations = equations
    }

    public func hasIncomplete(_ text: String) -> Bool {
        equations.contains { !$0.value.complete && text.contains($0.key) }
    }

    public func restore(_ text: String) -> String {
        equations.reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value.source) }
    }

    /// Escape literal dollars before handing prose to the math library, whose
    /// dollar recognizer otherwise treats currency as an equation.
    public func latex(_ text: String) -> String? {
        guard equations.contains(where: { $0.value.complete && text.contains($0.key) }) else { return nil }
        var escaped = ""
        for char in text {
            if char == "$", escaped.last != "\\" { escaped += "\\" }
            escaped.append(char)
        }
        return restore(escaped)
    }
}
