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
			The user is dictating into a terminal/command-line application. Format the output strictly as a raw shell command or sequence of commands:
			- Return ONLY the executable command line. Do NOT wrap the command in markdown code fences or blocks (e.g., do NOT use ```bash or ```).
			- Convert spoken punctuation or names into code syntax: e.g. "dash dash" to "--", "hyphen" to "-", "slash" to "/", "dot" to ".", "space" to " ", "star" to "*".
			- Use lowercase for command names, parameters, and flags unless specifically stated or required (e.g., "git add dot" → "git add .", "git commit status message" → "git commit -m \"status message\"").
			- Remove all filler words, self-corrections, and conversational explanations completely.
			- Do not add periods, punctuation, or other sentence-ending characters at the end of the command line.
			- If dictating multiple commands, separate them onto their own lines or join them with "&&" depending on context.
			"""
		case .email:
			return """
			The user is dictating into an email application. Format the output strictly as a well-structured email message:
			- Format the greeting (e.g., "Dear Name,", "Hi Name,") on its own line at the start, followed by a blank line.
			- Separate body paragraphs with clean blank lines for readability.
			- Use a professional yet natural tone.
			- Add a sign-off (e.g., "Best regards,", "Thanks,", "Sincerely,") on its own line at the end only if the dictation implies closing.
			- Remove all spoken formatting cues (like "new line", "comma", "period", "bullet point") and replace them with actual formatting.
			- Clean up filler words and self-corrections.
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
			The user is dictating into a web browser. Format the output based on the website's context:
			- If on an email site (Gmail, Outlook, Yahoo Mail), strictly format the output as a well-structured email: put the greeting at the top, separate the body paragraphs with blank lines, and put the sign-off at the bottom.
			- If on a messaging or chat site (Slack web, WhatsApp web, Discord web), format as a concise, conversational message.
			- If on a document editor (Google Docs, Notion), format as organized text with proper formatting and structure.
			- Default: clean up filler words, add punctuation, and format nicely without conversational filler.
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