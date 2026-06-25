import Foundation

public enum AppCategory: String, Codable, CaseIterable, Equatable, Sendable {
	case terminal
	case email
	case codeEditor
	case chat
	case browser
	case notes
	case document
	case spreadsheet
	case other

	public var displayName: String {
		switch self {
		case .terminal: return "Terminal"
		case .email: return "Email"
		case .codeEditor: return "Code Editor"
		case .chat: return "Chat"
		case .browser: return "Browser"
		case .notes: return "Notes"
		case .document: return "Document"
		case .spreadsheet: return "Spreadsheet"
		case .other: return "Other"
		}
	}

	public var systemPromptContext: String {
		switch self {
		case .terminal:
			return """
			The user is dictating into a terminal/command-line application. Format the output as a command or sequence of commands:
			- Use lowercase unless the user clearly says proper nouns or acronyms
			- Remove filler words and self-corrections entirely
			- Do not add periods or other sentence-ending punctuation
			- If dictating multiple commands, put each on its own line
			- Convert natural language to appropriate command syntax where obvious (e.g., "list all files" → "ls -la")
			- Preserve flags and options the user specifies
			"""
		case .email:
			return """
			The user is dictating into an email application. Format the output as a well-structured email:
			- Add an appropriate greeting if the content suggests one
			- Use proper paragraphs and punctuation
			- Professional but natural tone
			- Add a sign-off (e.g., "Best regards,") only if the content suggests the email is complete
			- Clean up filler words and self-corrections
			"""
		case .codeEditor:
			return """
			The user is dictating into a code editor. Format the output appropriately for a programming context:
			- If the content sounds like code, format it as code with appropriate syntax
			- If the content sounds like a comment, format it as a code comment
			- Use proper indentation and formatting conventions
			- Preserve technical terms, variable names, and function names as spoken
			- Clean up filler words but keep technical precision
			- If dictating variable names or identifiers, use camelCase or snake_case as appropriate for the likely language
			"""
		case .chat:
			return """
			The user is dictating into a chat/messaging application. Format the output as a natural message:
			- Keep it conversational and concise
			- Clean up filler words (um, uh, like, you know) but preserve the casual tone
			- Add punctuation for readability
			- Do not add emoji unless the user said them explicitly
			- Handle self-corrections: use the corrected version
			"""
		case .browser:
			return """
			The user is dictating into a web browser. Format the output based on the likely context:
			- If on an email site (Gmail, Outlook, etc.), format as an email
			- If on a social media site, format as a post or message
			- If on a document editing site, format as document text
			- Default: clean up with proper punctuation and grammar without over-formatting
			"""
		case .notes:
			return """
			The user is dictating into a note-taking application. Format the output as organized notes:
			- Use bullet points for lists of items
			- Add headers for topic changes (e.g., "## " prefix)
			- Preserve the user's structure and organization intent
			- Clean up filler words but keep the content complete
			- Proper punctuation and capitalization
			"""
		case .document:
			return """
			The user is dictating into a document editor. Format the output as well-structured prose:
			- Use proper paragraphs with clear topic sentences
			- Correct grammar and punctuation
			- Maintain professional tone appropriate for a document
			- Clean up filler words and self-corrections
			- Preserve the user's intended meaning precisely
			"""
		case .spreadsheet:
			return """
			The user is dictating into a spreadsheet application. Format the output appropriately:
			- If dictating data, format as tab-separated values or clear entries
			- If dictating formulas, use appropriate function syntax
			- Clean up filler words
			- Preserve numbers and mathematical expressions accurately
			"""
		case .other:
			return ""
		}
	}

	public static func fromBundleID(_ bundleID: String) -> AppCategory {
		let mapping: [String: AppCategory] = [
			"com.apple.Terminal": .terminal,
			"com.googlecode.iterm2": .terminal,
			"dev.warp.Warp-Stable": .terminal,
			"org.alacritty": .terminal,
			"io.alacritty": .terminal,
			"com.googlecode.macvim": .terminal,
			"org.vim.MacVim": .terminal,
			"com.github.wez.wezterm": .terminal,
			"net.kovidgoyal.kitty": .terminal,

			"com.apple.mail": .email,
			"com.microsoft.Outlook": .email,
			"com.freron.MailMate": .email,
			"com.apple.mobileme.mail": .email,

			"com.apple.dt.Xcode": .codeEditor,
			"com.microsoft.VSCode": .codeEditor,
			"com.microsoft.VSCodeInsiders": .codeEditor,
			"com.sublimetext.4": .codeEditor,
			"com.sublimetext.3": .codeEditor,
			"com.jetbrains.intellij": .codeEditor,
			"com.jetbrains.intellij.ce": .codeEditor,
			"com.jetbrains.pycharm": .codeEditor,
			"com.jetbrains.webstorm": .codeEditor,
			"com.google.AndroidStudio": .codeEditor,
			"dev.zed.Zed": .codeEditor,
			"com.macromates.TextMate": .codeEditor,
			"com.panic.Nova": .codeEditor,
			"org.gnu.Emacs": .codeEditor,
			"org.vim": .codeEditor,

			"com.apple.MobileSMS": .chat,
			"com.slack.mac": .chat,
			"com.hnc.Discord": .chat,
			"com.microsoft.teams": .chat,
			"com.telegram.telegram": .chat,
			"com.whatsapp.WhatsApp": .chat,
			"org.signal.Signal": .chat,
			"co.monal.Monal": .chat,
			"com.skype.skype": .chat,
			"com.facebook.Messenger": .chat,

			"com.apple.Safari": .browser,
			"com.google.Chrome": .browser,
			"org.mozilla.firefox": .browser,
			"com.microsoft.edgemac": .browser,
			"com.brave.Browser": .browser,
			"company.thebrowser.Browser": .browser,
			"com.vivaldi.Vivaldi": .browser,
			"com.operasoftware.Opera": .browser,
			"com.google.Chrome.canary": .browser,

			"com.apple.Notes": .notes,
			"md.notion": .notes,
			"com.culturedcode.ThingsMac": .notes,
			"com.agiletortoise.Drafts-OSX": .notes,
			"com.brettterpstra.nvalt": .notes,
			"notion.id": .notes,
			"com.bear.bear-macos": .notes,
			"com.apple.iWork.Keynote": .notes,

			"com.apple.iWork.Pages": .document,
			"com.microsoft.Word": .document,
			"com.microsoft.Powerpoint": .document,
			"org.libreoffice.script": .document,

			"com.apple.iWork.Numbers": .spreadsheet,
			"com.microsoft.Excel": .spreadsheet,
		]
		return mapping[bundleID] ?? .other
	}
}

public struct AppContext: Codable, Equatable, Sendable {
	public let bundleID: String
	public let appName: String
	public let url: String?

	public init(bundleID: String, appName: String, url: String? = nil) {
		self.bundleID = bundleID
		self.appName = appName
		self.url = url
	}

	public var category: AppCategory {
		AppCategory.fromBundleID(bundleID)
	}

	public var browserURLHost: String? {
		guard let url, let components = URLComponents(string: url), let host = components.host else {
			return nil
		}
		return host
	}
}