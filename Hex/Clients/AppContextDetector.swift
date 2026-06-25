import AppKit
import HexCore

extension AppContext {
	public static func detect(bundleID: String?, appName: String?) -> AppContext? {
		guard let bundleID, let appName else {
			return nil
		}

		var url: String?
		let category = AppCategory.fromBundleID(bundleID)
		if category == .browser {
			url = detectBrowserURL(bundleID: bundleID)
		}

		return AppContext(bundleID: bundleID, appName: appName, url: url)
	}

	@MainActor
	public static func detectFromFrontmostApp() -> AppContext? {
		guard let activeApp = NSWorkspace.shared.frontmostApplication,
		      let bundleID = activeApp.bundleIdentifier,
		      let appName = activeApp.localizedName else {
			return nil
		}

		var url: String?
		let category = AppCategory.fromBundleID(bundleID)
		if category == .browser {
			url = detectBrowserURL(bundleID: bundleID)
		}

		return AppContext(bundleID: bundleID, appName: appName, url: url)
	}

	private static func detectBrowserURL(bundleID: String) -> String? {
		let script: String
		switch bundleID {
		case "com.apple.Safari":
			script = "tell application \"Safari\" to get URL of current tab of front window"
		case "com.google.Chrome", "com.google.Chrome.canary":
			script = "tell application \"Google Chrome\" to get URL of active tab of front window"
		case "company.thebrowser.Browser":
			script = "tell application \"Arc\" to get URL of active tab of front window"
		case "org.mozilla.firefox":
			return nil
		case "com.microsoft.edgemac":
			script = "tell application \"Microsoft Edge\" to get URL of active tab of front window"
		case "com.brave.Browser":
			script = "tell application \"Brave Browser\" to get URL of active tab of front window"
		default:
			return nil
		}

		var error: NSDictionary?
		let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
		if error != nil {
			return nil
		}
		return result?.stringValue
	}
}