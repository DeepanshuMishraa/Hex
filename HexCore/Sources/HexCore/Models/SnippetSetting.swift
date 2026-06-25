import Foundation

public struct SnippetSetting: Codable, Equatable, Identifiable, Sendable {
	public var id: UUID
	public var isEnabled: Bool
	public var shortcut: String
	public var content: String

	public init(
		id: UUID = UUID(),
		isEnabled: Bool = true,
		shortcut: String,
		content: String
	) {
		self.id = id
		self.isEnabled = isEnabled
		self.shortcut = shortcut
		self.content = content
	}
}

public enum SnippetApplier {
	public static func apply(_ text: String, snippets: [SnippetSetting]) -> String {
		guard !snippets.isEmpty else { return text }
		var output = text
		// Sort snippets by shortcut length descending so longer shortcuts are replaced first
		let sortedSnippets = snippets.filter { $0.isEnabled && !$0.shortcut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
			.sorted { $0.shortcut.count > $1.shortcut.count }

		for snippet in sortedSnippets {
			let trimmed = snippet.shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
			let escaped = NSRegularExpression.escapedPattern(for: trimmed)
			let pattern = "(?<!\\w)\(escaped)(?!\\w)"
			let replacement = processEscapeSequences(snippet.content)
			let escapedReplacement = replacement.replacingOccurrences(of: "\\", with: "\\\\")
			output = output.replacingOccurrences(
				of: pattern,
				with: escapedReplacement,
				options: [.regularExpression, .caseInsensitive]
			)
		}
		return output
	}

	private static func processEscapeSequences(_ string: String) -> String {
		let placeholder = "\u{0000}"
		return string
			.replacingOccurrences(of: "\\\\", with: placeholder)
			.replacingOccurrences(of: "\\n", with: "\n")
			.replacingOccurrences(of: "\\t", with: "\t")
			.replacingOccurrences(of: "\\r", with: "\r")
			.replacingOccurrences(of: placeholder, with: "\\")
	}
}
