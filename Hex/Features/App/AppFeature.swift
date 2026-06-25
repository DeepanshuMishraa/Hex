import AppKit
import ComposableArchitecture
import Dependencies
import HexCore
import SwiftUI

@Reducer
struct AppFeature {
  enum ActiveTab: Equatable, Hashable {
    case home
    case dictionary
    case snippets
    case style
    case notes
    case settings
    case help
  }

	@ObservableState
	struct State {
		var transcription: TranscriptionFeature.State = .init()
		var settings: SettingsFeature.State = .init()
		var history: HistoryFeature.State = .init()
		var activeTab: ActiveTab = .home
		@Shared(.hexSettings) var hexSettings: HexSettings
		@Shared(.modelBootstrapState) var modelBootstrapState: ModelBootstrapState

    // Permission state
    var microphonePermission: PermissionStatus = .notDetermined
    var accessibilityPermission: PermissionStatus = .notDetermined
    var inputMonitoringPermission: PermissionStatus = .notDetermined
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case transcription(TranscriptionFeature.Action)
    case settings(SettingsFeature.Action)
    case history(HistoryFeature.Action)
    case setActiveTab(ActiveTab)
    case task
    case pasteLastTranscript

    // Permission actions
    case checkPermissions
    case permissionsUpdated(mic: PermissionStatus, acc: PermissionStatus, input: PermissionStatus)
    case appActivated
    case requestMicrophone
    case requestAccessibility
    case requestInputMonitoring
    case modelStatusEvaluated(Bool)
  }

  @Dependency(\.keyEventMonitor) var keyEventMonitor
  @Dependency(\.pasteboard) var pasteboard
  @Dependency(\.transcription) var transcription
  @Dependency(\.permissions) var permissions

  var body: some ReducerOf<Self> {
    BindingReducer()

    Scope(state: \.transcription, action: \.transcription) {
      TranscriptionFeature()
    }

    Scope(state: \.settings, action: \.settings) {
      SettingsFeature()
    }

    Scope(state: \.history, action: \.history) {
      HistoryFeature()
    }

    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case .task:
        return .merge(
          startPasteLastTranscriptMonitoring(),
          ensureSelectedModelReadiness(),
          startPermissionMonitoring()
        )

      case .pasteLastTranscript:
        @Shared(.transcriptionHistory) var transcriptionHistory: TranscriptionHistory
        guard let lastTranscript = transcriptionHistory.history.first?.text else {
          return .none
        }
        return .run { _ in
          await pasteboard.paste(lastTranscript)
        }

      case .transcription(.modelMissing):
        HexLog.app.notice("Model missing - activating app and switching to settings")
        state.activeTab = .settings
        state.settings.shouldFlashModelSection = true
        return .run { send in
          await MainActor.run {
            HexLog.app.notice("Activating app for model missing")
            NSApplication.shared.activate(ignoringOtherApps: true)
          }
          try? await Task.sleep(for: .seconds(2))
          await send(.settings(.set(\.shouldFlashModelSection, false)))
        }

      case .transcription:
        return .none

      case .settings:
        return .none

      case .settings(.delegate(.permissionChanged(let mic))):
        state.microphonePermission = mic
        // Also re-check all permissions to keep the full state fresh
        return .send(.checkPermissions)

      case .history(.navigateToSettings):
        state.activeTab = .settings
        return .none
      case .history:
        return .none
		case let .setActiveTab(tab):
			state.activeTab = tab
			return .none

      // Permission handling
      case .checkPermissions:
        return .run { send in
          async let mic = permissions.microphoneStatus()
          async let acc = permissions.accessibilityStatus()
          async let input = permissions.inputMonitoringStatus()
          await send(.permissionsUpdated(mic: mic, acc: acc, input: input))
        }

      case let .permissionsUpdated(mic, acc, input):
        state.microphonePermission = mic
        state.accessibilityPermission = acc
        state.inputMonitoringPermission = input
        return .none

      case .appActivated:
        return .send(.checkPermissions)

      case .requestMicrophone:
        return .run { send in
          _ = await permissions.requestMicrophone()
          await send(.checkPermissions)
        }

      case .requestAccessibility:
        return .run { send in
          await permissions.requestAccessibility()
          for _ in 0..<10 {
            try? await Task.sleep(for: .seconds(1))
            await send(.checkPermissions)
          }
        }

      case .requestInputMonitoring:
        return .run { send in
          _ = await permissions.requestInputMonitoring()
          for _ in 0..<10 {
            try? await Task.sleep(for: .seconds(1))
            await send(.checkPermissions)
          }
        }

      case .modelStatusEvaluated:
        return .none
      }
    }
  }

  private func startPasteLastTranscriptMonitoring() -> Effect<Action> {
    .run { send in
      @Shared(.isSettingPasteLastTranscriptHotkey) var isSettingPasteLastTranscriptHotkey: Bool
      @Shared(.hexSettings) var hexSettings: HexSettings

      let token = keyEventMonitor.handleKeyEvent { keyEvent in
        if isSettingPasteLastTranscriptHotkey {
          return false
        }

        guard let pasteHotkey = hexSettings.pasteLastTranscriptHotkey,
              let key = keyEvent.key,
              key == pasteHotkey.key,
              keyEvent.modifiers.matchesExactly(pasteHotkey.modifiers) else {
          return false
        }

        MainActor.assumeIsolated {
          send(.pasteLastTranscript)
        }
        return true
      }

      defer { token.cancel() }

      await withTaskCancellationHandler {
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(60))
        }
      } onCancel: {
        token.cancel()
      }
    }
  }

  private func ensureSelectedModelReadiness() -> Effect<Action> {
    .run { send in
      @Shared(.hexSettings) var hexSettings: HexSettings
      @Shared(.modelBootstrapState) var modelBootstrapState: ModelBootstrapState
      let selectedModel = hexSettings.selectedModel
      guard !selectedModel.isEmpty else {
        await send(.modelStatusEvaluated(false))
        return
      }
      let isReady = await transcription.isModelDownloaded(selectedModel)
      $modelBootstrapState.withLock { state in
        state.modelIdentifier = selectedModel
        if state.modelDisplayName?.isEmpty ?? true {
          state.modelDisplayName = selectedModel
        }
        state.isModelReady = isReady
        if isReady {
          state.lastError = nil
          state.progress = 1
        } else {
          state.progress = 0
        }
      }
      await send(.modelStatusEvaluated(isReady))
    }
  }

  private func startPermissionMonitoring() -> Effect<Action> {
    .run { send in
      await send(.checkPermissions)
      for await activation in permissions.observeAppActivation() {
        if case .didBecomeActive = activation {
          await send(.appActivated)
        }
      }
    }
  }
}

// MARK: - App View

struct AppView: View {
  @Bindable var store: StoreOf<AppFeature>
  @State private var isSidebarVisible = true
  @State private var isStatsPresented = false
  @State private var isPersonalisationWizardPresented = false

  private var userName: String {
    let name = NSFullUserName()
    if name.isEmpty {
      let loginName = NSUserName()
      return loginName.isEmpty ? "Yuxuan" : loginName
    }
    return name.components(separatedBy: " ").first ?? "Yuxuan"
  }

  private var wordCount: Int {
    store.state.history.transcriptionHistory.history.reduce(0) { count, transcript in
      count + transcript.text.split(separator: " ").count
    }
  }

  private var dailyStreak: Int {
    let history = store.state.history.transcriptionHistory.history
    guard !history.isEmpty else { return 0 }
    
    let calendar = Calendar.current
    let dates = Set(history.map { calendar.startOfDay(for: $0.timestamp) })
    let today = calendar.startOfDay(for: Date())
    
    var currentCheckDate = today
    var streak = 0
    
    if !dates.contains(today) {
      guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
      if !dates.contains(yesterday) {
        return 0
      }
      currentCheckDate = yesterday
    }
    
    while dates.contains(currentCheckDate) {
      streak += 1
      guard let prevDate = calendar.date(byAdding: .day, value: -1, to: currentCheckDate) else { break }
      currentCheckDate = prevDate
    }
    
    return streak
  }

  private var averageWPM: Int {
    let history = store.state.history.transcriptionHistory.history
    guard !history.isEmpty else { return 0 }
    
    var totalWords = 0
    var totalSeconds: Double = 0.0
    
    for transcript in history {
      let words = transcript.text.split(separator: " ").count
      if transcript.duration > 0.5 && words > 0 {
        totalWords += words
        totalSeconds += transcript.duration
      }
    }
    
    guard totalSeconds > 1.0 else { return 0 }
    let wpm = Double(totalWords) / (totalSeconds / 60.0)
    return min(250, max(0, Int(round(wpm))))
  }

  private var uniqueAppsCount: Int {
    let history = store.state.history.transcriptionHistory.history
    let appNames = Set(history.compactMap { $0.sourceAppName })
    return max(1, appNames.count)
  }

  private var displayTranscripts: [Transcript] {
    if store.state.history.transcriptionHistory.history.isEmpty {
      let calendar = Calendar.current
      let today = Date()
      
      let t1 = Transcript(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        timestamp: calendar.date(bySettingHour: 12, minute: 38, second: 0, of: today) ?? today,
        text: "I want to draft a email for holiday seasons",
        audioPath: URL(fileURLWithPath: ""),
        duration: 5.0
      )
      let t2 = Transcript(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        timestamp: calendar.date(bySettingHour: 12, minute: 38, second: 10, of: today) ?? today,
        text: "Email is ready. Could you help me to check if this sentence is right?",
        audioPath: URL(fileURLWithPath: ""),
        duration: 8.0
      )
      let t3 = Transcript(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        timestamp: calendar.date(bySettingHour: 12, minute: 38, second: 20, of: today) ?? today,
        text: "Audio is silence",
        audioPath: URL(fileURLWithPath: ""),
        duration: 2.0
      )
      let t4 = Transcript(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        timestamp: calendar.date(bySettingHour: 12, minute: 39, second: 0, of: today) ?? today,
        text: "Could you please review this attachment and provide your feedback?",
        audioPath: URL(fileURLWithPath: ""),
        duration: 6.0
      )
      let t5 = Transcript(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        timestamp: calendar.date(bySettingHour: 12, minute: 40, second: 0, of: today) ?? today,
        text: "I need assistance in finalizing the presentation for tomorrow's meeting.",
        audioPath: URL(fileURLWithPath: ""),
        duration: 9.0
      )
      let t6 = Transcript(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
        timestamp: calendar.date(bySettingHour: 12, minute: 41, second: 0, of: today) ?? today,
        text: "Let's schedule a call to discuss the project updates.",
        audioPath: URL(fileURLWithPath: ""),
        duration: 4.0
      )
      return [t1, t2, t3, t4, t5, t6]
    } else {
      return store.state.history.transcriptionHistory.history.sorted(by: { $0.timestamp < $1.timestamp })
    }
  }

  var body: some View {
    ZStack {
      HStack(spacing: 0) {
        if isSidebarVisible {
          sidebar
            .frame(width: 220)
            .background(AppTheme.sidebarBackground)
            .transition(.move(edge: .leading))
        }

        Divider()
          .background(Color.primary.opacity(0.1))

        detailContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(AppTheme.detailBackground)
      }
      .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSidebarVisible)

      if isStatsPresented {
        StatisticsModal(
          wordCount: wordCount,
          dailyStreak: dailyStreak,
          averageWPM: averageWPM,
          uniqueAppsCount: uniqueAppsCount,
          onDismiss: { isStatsPresented = false }
        )
      }

      if isPersonalisationWizardPresented {
        PersonalisationWizardModal(onDismiss: { isPersonalisationWizardPresented = false })
      }
    }
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Button(action: {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isSidebarVisible.toggle()
          }
        }) {
          Image(systemName: "sidebar.left")
        }
        .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
      }
    }
    .task {
      await store.send(.task).finish()
    }
  }

  @ViewBuilder
  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer()
        .frame(height: 24)

      HStack(spacing: 6) {
        HStack(alignment: .center, spacing: 3) {
          RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.primary)
            .frame(width: 3, height: 12)
          RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.primary)
            .frame(width: 3, height: 20)
          RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.primary)
            .frame(width: 3, height: 15)
        }
        
        Text("Tick")
          .font(TickFont.headingFunc(20, weight: .semibold))
          .foregroundStyle(TickColor.textPrimary)
      }
      .padding(.horizontal, 20)
      .padding(.top, 8)
      .padding(.bottom, 16)
      
      VStack(alignment: .leading, spacing: 4) {
        SidebarItem(icon: "square.grid.2x2", title: "Home", isActive: store.activeTab == .home) {
          store.send(.setActiveTab(.home))
        }
        SidebarItem(icon: "book", title: "Dictionary", isActive: store.activeTab == .dictionary) {
          store.send(.setActiveTab(.dictionary))
        }
        SidebarItem(icon: "scissors", title: "Snippets", isActive: store.activeTab == .snippets) {
          store.send(.setActiveTab(.snippets))
        }
        SidebarItem(icon: "slider.horizontal.3", title: "Style", isActive: store.activeTab == .style) {
          store.send(.setActiveTab(.style))
        }
        SidebarItem(icon: "note.text", title: "Notes", isActive: store.activeTab == .notes) {
          store.send(.setActiveTab(.notes))
        }
      }
      .padding(.horizontal, 12)
      
      Spacer()
      
      VStack(alignment: .leading, spacing: 4) {
        SidebarItem(icon: "gearshape", title: "Setting", isActive: store.activeTab == .settings) {
          store.send(.setActiveTab(.settings))
        }
        SidebarItem(icon: "questionmark.circle", title: "Help", isActive: store.activeTab == .help) {
          store.send(.setActiveTab(.help))
        }
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 20)
    }
  }

  @ViewBuilder
  private var detailContent: some View {
    VStack(spacing: 0) {
      if store.activeTab == .home {
        homeHeader
      } else {
        standardHeader
      }
      
      Divider()
        .background(Color.primary.opacity(0.05))
      
      ScrollView {
        VStack(spacing: 0) {
          switch store.activeTab {
          case .home:
            homeTabContent
          case .dictionary:
            DictionaryTabView(store: store)
              .padding(24)
          case .snippets:
            SnippetsTabView()
              .padding(24)
          case .style:
            StyleTabView(isWizardPresented: $isPersonalisationWizardPresented)
              .padding(24)
          case .notes:
            NotesTabView()
              .padding(24)
          case .settings:
            SettingsView(
              store: store.scope(state: \.settings, action: \.settings),
              microphonePermission: store.microphonePermission,
              accessibilityPermission: store.accessibilityPermission,
              inputMonitoringPermission: store.inputMonitoringPermission
            )
            .padding(24)
          case .help:
            HelpTabView()
              .padding(24)
          }
        }
        .frame(maxWidth: .infinity, alignment: .top)
      }
    }
  }

  private var homeHeader: some View {
    HStack {
      Text("Welcome back, \(userName)")
        .font(TickFont.headingFunc(22, weight: .semibold))
        .foregroundStyle(TickColor.textPrimary)
      
      HStack(spacing: 8) {
        Button(action: { isStatsPresented = true }) {
          StatPill(emoji: "🔥", text: "\(dailyStreak) \(dailyStreak == 1 ? "day" : "days")")
        }
        .buttonStyle(.plain)
        
        Button(action: { isStatsPresented = true }) {
          StatPill(emoji: "🚀", text: "\(wordCount) \(wordCount == 1 ? "word" : "words")")
        }
        .buttonStyle(.plain)
        
        Button(action: { isStatsPresented = true }) {
          StatPill(emoji: "👋", text: "\(averageWPM) WPM")
        }
        .buttonStyle(.plain)
      }
      .padding(.leading, 12)
      
      Spacer()
      
      HStack(spacing: 16) {
        // Notifications and user avatar removed per request
      }
    }
    .padding(.leading, 24)
    .padding(.trailing, 24)
    .padding(.vertical, 16)
    .frame(height: 56)
  }

  private var standardHeader: some View {
    HStack {
      Text(tabTitle(store.activeTab))
        .font(TickFont.headingFunc(18, weight: .semibold))
        .foregroundStyle(TickColor.textPrimary)

      Spacer()
    }
    .padding(.leading, 24)
    .padding(.trailing, 24)
    .padding(.vertical, 16)
    .frame(height: 56)
  }
  
  private func tabTitle(_ tab: AppFeature.ActiveTab) -> String {
    switch tab {
    case .home: return "Home"
    case .dictionary: return "Dictionary"
    case .snippets: return "Snippets"
    case .style: return "Style"
    case .notes: return "Notes"
    case .settings: return "Settings"
    case .help: return "Help"
    }
  }

  @ViewBuilder
  private var homeTabContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      if !store.hexSettings.hasSelectedStyle {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 0) {
            Text("Make Tick sound like ")
              .font(TickFont.display(28, weight: .regular))
              .foregroundStyle(TickColor.textPrimary)
            Text("you")
              .font(TickFont.displayItalic(28))
              .foregroundStyle(TickColor.brand)
          }

          Text("Tick adapts to how you write in different apps. Personalize your style for messages, work chats, emails, and other apps so every word sounds like you.")
            .font(TickFont.bodyFunc(14))
            .foregroundStyle(TickColor.textPrimary)
            .opacity(0.75)
            .lineSpacing(4)
            .padding(.trailing, 40)

          Button(action: {
            store.send(.setActiveTab(.style))
          }) {
            Text("Start now")
              .font(TickFont.labelFunc(13, weight: .medium))
              .foregroundColor(.white)
              .padding(.horizontal, 18)
              .padding(.vertical, 9)
              .background(TickColor.textPrimary)
              .cornerRadius(8)
          }
          .buttonStyle(.plain)
          .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.bannerBackground)
        .cornerRadius(16)
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
      }
      
      HStack {
        Text("TODAY")
          .font(TickFont.headingFunc(11, weight: .bold))
          .foregroundStyle(TickColor.textSecondary)
        Spacer()
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 10)
      
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(displayTranscripts.enumerated()), id: \.element.id) { index, transcript in
          TranscriptRow(
            transcript: transcript,
            isPlaying: store.state.history.playingTranscriptID == transcript.id,
            onPlay: { store.send(.history(.playTranscript(transcript.id))) },
            onCopy: { store.send(.history(.copyToClipboard(transcript.text))) },
            onDelete: { store.send(.history(.deleteTranscript(transcript.id))) }
          )
          
          if index < displayTranscripts.count - 1 {
            Divider()
              .background(Color.primary.opacity(0.05))
          }
        }
      }
      .background(Color(nsColor: .controlBackgroundColor))
      .cornerRadius(12)
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.primary.opacity(0.06), lineWidth: 1)
      )
      .padding(.horizontal, 24)
      .padding(.bottom, 24)
    }
  }
}

// MARK: - Support Views

struct SidebarItem: View {
  let icon: String
  let title: String
  let isActive: Bool
  let action: () -> Void
  
  @State private var isHovered = false
  
  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .font(TickFont.labelFunc(13, weight: .medium))
          .foregroundColor(isActive ? .primary : .secondary)
          .frame(width: 16, height: 16)
        
        Text(title)
          .font(TickFont.labelFunc(13, weight: isActive ? Font.Weight.medium : Font.Weight.regular))
          .foregroundColor(isActive ? .primary : .secondary)
        
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(isActive ? Color.primary.opacity(0.08) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
      )
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}

struct StatPill: View {
  let emoji: String
  let text: String

  var body: some View {
    HStack(spacing: 4) {
      Text(emoji)
        .font(TickFont.captionFunc(13))
      Text(text)
        .font(TickFont.labelFunc(12, weight: .medium))
        .foregroundStyle(TickColor.textPrimary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(
      Capsule()
        .fill(TickColor.canvas)
    )
  }
}

struct TranscriptRow: View {
  let transcript: Transcript
  let isPlaying: Bool
  let onPlay: () -> Void
  let onCopy: () -> Void
  let onDelete: () -> Void
  
  @State private var isHovered = false
  @State private var showCopied = false
  @State private var copyTask: Task<Void, Error>?
  
  var body: some View {
    HStack(alignment: .center, spacing: 20) {
      Text(transcript.timestamp.formatted(date: .omitted, time: .shortened))
        .font(TickFont.captionFunc(13))
        .foregroundStyle(TickColor.textSecondary)
        .frame(width: 75, alignment: .leading)
      
      HStack(spacing: 6) {
        if transcript.text.lowercased().contains("silence") || transcript.text.lowercased().contains("slince") {
          Text(transcript.text)
            .font(TickFont.captionFunc(13))
            .italic()
            .foregroundColor(.secondary.opacity(0.8))
          
          Image(systemName: "info.circle")
            .font(TickFont.captionFunc(12))
            .foregroundColor(.secondary.opacity(0.8))
        } else {
          Text(transcript.text)
            .font(TickFont.captionFunc(13))
            .foregroundStyle(TickColor.textPrimary)
        }
      }
      
      Spacer()
      
      HStack(spacing: 12) {
        if isHovered {
          Button(action: {
            onCopy()
            showCopyAnimation()
          }) {
            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
              .font(TickFont.captionFunc(12))
              .foregroundColor(showCopied ? .green : .secondary)
          }
          .buttonStyle(.plain)
          
          Button(action: {}) {
            Image(systemName: "flag")
              .font(TickFont.captionFunc(12))
              .foregroundStyle(TickColor.textSecondary)
          }
          .buttonStyle(.plain)
          
          Menu {
            Button(isPlaying ? "Stop Audio" : "Play Audio", action: onPlay)
            Button("Delete", role: .destructive, action: onDelete)
          } label: {
            Image(systemName: "ellipsis")
              .font(TickFont.captionFunc(12))
              .foregroundStyle(TickColor.textSecondary)
          }
          .menuStyle(.button)
          .buttonStyle(.plain)
        }
      }
      .frame(width: 80, alignment: .trailing)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 12)
    .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
    .contentShape(Rectangle())
    .onHover { isHovered = $0 }
    .onDisappear {
      copyTask?.cancel()
    }
  }
  
  private func showCopyAnimation() {
    copyTask?.cancel()
    copyTask = Task {
      withAnimation { showCopied = true }
      try await Task.sleep(for: .seconds(1.5))
      withAnimation { showCopied = false }
    }
  }
}

// MARK: - Custom Controls

struct CustomSegmentedControl: View {
  let items: [String]
  @Binding var selectedIndex: Int
  
  var body: some View {
    HStack(spacing: 16) {
      ForEach(Array(items.enumerated()), id: \.element) { index, item in
        Button(action: { selectedIndex = index }) {
          VStack(spacing: 6) {
            Text(item)
              .font(TickFont.labelFunc(13, weight: selectedIndex == index ? Font.Weight.semibold : Font.Weight.medium))
              .foregroundColor(selectedIndex == index ? .primary : .secondary)
            
            Rectangle()
              .fill(selectedIndex == index ? Color.primary : Color.clear)
              .frame(height: 2)
          }
        }
        .buttonStyle(.plain)
      }
    }
  }
}

// MARK: - Modals

struct StatisticsModal: View {
  let wordCount: Int
  let dailyStreak: Int
  let averageWPM: Int
  let uniqueAppsCount: Int
  let onDismiss: () -> Void
  
  private var dailyStreakDescription: String {
    if dailyStreak == 0 {
      return "Start recording to build your daily streak!"
    } else if dailyStreak < 3 {
      return "You are off to a great start!"
    } else if dailyStreak < 7 {
      return "Keep it up, you're on a roll!"
    } else {
      return "Incredible dedication, you're unstoppable!"
    }
  }

  private var wpmDescription: String {
    if averageWPM == 0 {
      return "Speak to calculate your words per minute."
    } else if averageWPM < 80 {
      return "Use Tick more to see your WPM improve."
    } else if averageWPM < 130 {
      return "Nice job, you speak at a good, natural pace!"
    } else {
      return "Wow, you dictate fast! Professional level speed."
    }
  }

  private var appsDescription: String {
    if uniqueAppsCount <= 1 {
      return "Flowing in your primary app. Try using Tick in other apps!"
    } else if uniqueAppsCount < 5 {
      return "You're starting to flow across different apps."
    } else {
      return "You've been flowing nearly everywhere!"
    }
  }

  private var coverLettersCount: Int {
    max(1, wordCount / 120)
  }

  var body: some View {
    ZStack {
      Color.black.opacity(0.4)
        .edgesIgnoringSafeArea(.all)
        .onTapGesture {
          onDismiss()
        }
      
      VStack(spacing: 0) {
        HStack {
          Spacer()
          Button(action: onDismiss) {
            Image(systemName: "xmark")
              .font(TickFont.labelFunc(12))
              .foregroundStyle(TickColor.textSecondary)
              .frame(width: 28, height: 28)
              .background(Circle().fill(TickColor.canvas))
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)

        HStack(spacing: 6) {
          Text("You've been ")
            .font(TickFont.display(22, weight: .regular))
            .foregroundStyle(TickColor.textPrimary)
          Text("Ticking. Hard.")
            .font(TickFont.displayItalic(22))
            .foregroundStyle(TickColor.brand)
        }
        .padding(.bottom, 6)

        Text("Here's a personal snapshot of your productivity with Tick.")
          .font(TickFont.body)
          .foregroundStyle(TickColor.textSecondary)
          .padding(.bottom, 24)

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
          StatCard(title: "DAILY STREAK", mainText: "\(dailyStreak) \(dailyStreak == 1 ? "day" : "days") 🔥", description: dailyStreakDescription)
          StatCard(title: "AVERAGE SPEED", mainText: "\(averageWPM) WPM 👋", description: wpmDescription)
          StatCard(title: "TOTAL WORDS DICTATED", mainText: "\(wordCount) 🚀", description: "You've written \(coverLettersCount) \(coverLettersCount == 1 ? "cover letter" : "cover letters")!")
          StatCard(title: "TOTAL APPS USED", mainText: "\(uniqueAppsCount) \(uniqueAppsCount == 1 ? "app" : "apps") 🏆", description: appsDescription)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
      }
      .frame(width: 540)
      .background(Color.white)
      .cornerRadius(20)
      .overlay(
        RoundedRectangle(cornerRadius: 20)
          .stroke(Color.black.opacity(0.08), lineWidth: 1)
      )
      .shadow(color: Color.black.opacity(0.25), radius: 40, x: 0, y: 20)
    }
  }
}

struct StatCard: View {
  let title: String
  let mainText: String
  let description: String
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(TickFont.eyebrow)
        .tracking(0.8)
        .foregroundStyle(TickColor.textTertiary)

      Text(mainText)
        .font(TickFont.headingFunc(18, weight: .semibold))
        .foregroundStyle(TickColor.textPrimary)

      Text(description)
        .font(TickFont.caption)
        .foregroundStyle(TickColor.textSecondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(TickColor.stat)
    .cornerRadius(12)
  }
}

struct PersonalisationWizardModal: View {
  let onDismiss: () -> Void
  @Shared(.hexSettings) var hexSettings: HexSettings
  @State private var currentStep = 0

  var body: some View {
    ZStack {
      Color.black.opacity(0.4)
        .edgesIgnoringSafeArea(.all)
        .onTapGesture {
          onDismiss()
        }

      VStack(spacing: 0) {
        HStack {
          Spacer()
          Button(action: onDismiss) {
            Image(systemName: "xmark")
              .font(TickFont.labelFunc(12))
              .foregroundStyle(TickColor.textSecondary)
              .frame(width: 28, height: 28)
              .background(Circle().fill(TickColor.canvas))
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)

        // Step indicator (4 dashes)
        HStack(spacing: 6) {
          ForEach(0..<4) { index in
            RoundedRectangle(cornerRadius: 2)
              .fill(index == currentStep ? TickColor.textPrimary : TickColor.lineStrong)
              .frame(width: 36, height: 3)
          }
        }
        .padding(.bottom, 24)

        // Editorial headline with violet italic
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          (
            Text("How do you write in ")
              .font(TickFont.display(24, weight: .regular))
              .foregroundStyle(TickColor.textPrimary)
            + Text("other apps?")
              .font(TickFont.displayItalic(24))
              .foregroundStyle(TickColor.brand)
          )

          HStack(spacing: 6) {
            ChatGptIcon()
            NotionIcon()
            MediumIcon()
          }
          .padding(.leading, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 28)

        // Three style cards
        HStack(spacing: 16) {
          WizardStyleCard(
            title: "Formal.",
            label: "Caps + Punctuation",
            lines: [
              "So far, I am enjoying the new workout routine.",
              "I am excited for tomorrow's workout, especially after a full night of rest."
            ],
            isSelected: hexSettings.selectedStyleIndex == 0,
            action: { $hexSettings.withLock { $0.selectedStyleIndex = 0; $0.hasSelectedStyle = true } }
          )

          WizardStyleCard(
            title: "Casual",
            label: "Caps + Less punctuation",
            lines: [
              "So far I am enjoying the new workout routine.",
              "I am excited for tomorrow's workout especially after a full night of rest."
            ],
            isSelected: hexSettings.selectedStyleIndex == 1,
            action: { $hexSettings.withLock { $0.selectedStyleIndex = 1; $0.hasSelectedStyle = true } }
          )

          WizardStyleCard(
            title: "very casual",
            label: "No caps + Less punctuation",
            lines: [
              "so far i am enjoying the new workout routine",
              "i am excited for tomorrow's workout especially after a call or full night of rest"
            ],
            isSelected: hexSettings.selectedStyleIndex == 2,
            action: { $hexSettings.withLock { $0.selectedStyleIndex = 2; $0.hasSelectedStyle = true } }
          )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)

        // Action row
        HStack {
          Spacer()

          Button(action: onDismiss) {
            Text("Back")
              .font(TickFont.labelFunc(13, weight: .medium))
              .foregroundStyle(TickColor.textPrimary)
              .padding(.horizontal, 18)
              .padding(.vertical, 9)
              .background(
                RoundedRectangle(cornerRadius: 8)
                  .fill(TickColor.canvas)
                  .overlay(
                    RoundedRectangle(cornerRadius: 8)
                      .stroke(TickColor.line, lineWidth: 1)
                  )
              )
          }
          .buttonStyle(.plain)
          .padding(.trailing, 8)

          Button(action: {
            if currentStep < 3 {
              currentStep += 1
            } else {
              onDismiss()
            }
          }) {
            Text("Next")
              .font(TickFont.labelFunc(13))
              .foregroundStyle(.white)
              .padding(.horizontal, 18)
              .padding(.vertical, 9)
              .background(
                RoundedRectangle(cornerRadius: 8)
                  .fill(TickColor.textPrimary)
              )
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
      }
      .frame(width: 700)
      .background(
        RoundedRectangle(cornerRadius: 20)
          .fill(Color.white)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 20)
          .stroke(Color.black.opacity(0.08), lineWidth: 1)
      )
      .shadow(color: Color.black.opacity(0.3), radius: 40, x: 0, y: 20)
    }
  }
}

struct WizardStyleCard: View {
  let title: String
  let label: String
  let lines: [String]
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 14) {
        // Title in serif
        Text(title)
          .font(TickFont.display(22, weight: .regular))
          .foregroundStyle(TickColor.textPrimary)

        // Eyebrow label
        Text(label.uppercased())
          .font(TickFont.eyebrow)
          .tracking(0.6)
          .foregroundStyle(TickColor.textSecondary)

        // Divider
        Rectangle()
          .fill(TickColor.line)
          .frame(height: 1)
          .padding(.vertical, 2)

        // Example text
        VStack(alignment: .leading, spacing: 8) {
          ForEach(lines, id: \.self) { line in
            Text(line)
              .font(TickFont.bodyFunc(12))
              .foregroundStyle(TickColor.textPrimary)
              .lineSpacing(2)
          }
        }

        Spacer()
      }
      .padding(18)
      .frame(width: 200, height: 250, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 16)
          .fill(Color.white)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16)
          .stroke(
            isSelected ? TickColor.brand : (isHovered ? TickColor.lineStrong : TickColor.line),
            lineWidth: isSelected ? 2 : 1
          )
      )
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}

// MARK: - Dictionary Tab

struct DictionaryTabView: View {
  @Bindable var store: StoreOf<AppFeature>
  @State private var selectedTab = 0
  @State private var isBannerVisible = true
  @State private var mockItems = ["ARCHIMOOD", "MOCK", "GPT", "fellos", "16/9"]
  @State private var isAddingWord = false
  @State private var newWord = ""
  @State private var newReplacement = ""
  @State private var searchText = ""
  
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Dictionary")
          .font(TickFont.headingFunc(24, weight: .semibold))
          .foregroundStyle(TickColor.textPrimary)
        Spacer()
        Button(action: { isAddingWord = true }) {
          Text("Add new")
            .font(TickFont.labelFunc(13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(TickColor.textPrimary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
      }
      .padding(.bottom, 16)

      HStack {
        CustomSegmentedControl(items: ["All", "Personal", "Shared with team"], selectedIndex: $selectedTab)

        Spacer()

        HStack(spacing: 12) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(TickColor.textSecondary)
          Image(systemName: "arrow.up.arrow.down")
            .foregroundStyle(TickColor.textSecondary)
          Image(systemName: "arrow.clockwise")
            .foregroundStyle(TickColor.textSecondary)
        }
        .font(TickFont.bodyFunc(14))
      }
      .padding(.bottom, 20)
      
      Divider()
        .padding(.bottom, 20)
      
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if isBannerVisible {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Text("Tick speaks the way you speak.")
                  .font(TickFont.display(24, weight: .semibold))
                Spacer()
                Button(action: { isBannerVisible = false }) {
                  Image(systemName: "xmark")
                    .foregroundStyle(TickColor.textSecondary)
                }
                .buttonStyle(.plain)
              }
              
              Text("Tick learns your unique words and names - automatically or manually. **Add personal terms, company jargon, client names, or industry-specific lingo.** Share them with your team so everyone stays on the same page.")
                .font(TickFont.captionFunc(13))
                .foregroundStyle(TickColor.textSecondary)
                .lineSpacing(4)
                .padding(.trailing, 24)
              
              HStack(spacing: 8) {
                DictionaryPill(text: "Q3 Roadmap")
                DictionaryPill(text: "Whispr → Wisper")
                DictionaryPill(text: "SF MOMA")
                DictionaryPill(text: "Figma Jam")
                DictionaryPill(text: "Company name")
              }
              .padding(.vertical, 8)
              
              Button(action: { isAddingWord = true }) {
                Text("Add new word")
                  .font(TickFont.labelFunc(12))
                  .foregroundColor(.white)
                  .padding(.horizontal, 16)
                  .padding(.vertical, 8)
                  .background(Color.black)
                  .cornerRadius(8)
              }
              .buttonStyle(.plain)
            }
            .padding(24)
            .background(AppTheme.bannerBackground)
            .cornerRadius(16)
            .overlay(
              RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
            )
            .padding(.bottom, 20)
          }
          
          VStack(alignment: .leading, spacing: 0) {
            ForEach(mockItems.filter { searchText.isEmpty ? true : $0.lowercased().contains(searchText.lowercased()) }, id: \.self) { item in
              HStack {
                Text(item)
                  .font(TickFont.labelFunc(13))
                Text("✨")
                  .font(TickFont.captionFunc(11))
                
                Spacer()
                
                Button(action: {
                  mockItems.removeAll { $0 == item }
                }) {
                  Image(systemName: "trash")
                    .font(TickFont.captionFunc(11))
                    .foregroundStyle(TickColor.textSecondary)
                }
                .buttonStyle(.plain)
              }
              .padding(.vertical, 14)
              .padding(.horizontal, 16)
              
              Divider()
            }
          }
          .background(Color(nsColor: .controlBackgroundColor))
          .cornerRadius(12)
          .overlay(
            RoundedRectangle(cornerRadius: 12)
              .stroke(Color.primary.opacity(0.06), lineWidth: 1)
          )
        }
      }
      
      if isAddingWord {
        ZStack {
          Color.black.opacity(0.1)
            .edgesIgnoringSafeArea(.all)
          
          VStack(spacing: 16) {
            Text("Add new dictionary term")
              .font(TickFont.headingFunc(15, weight: .bold))
            
            TextField("Original text (e.g. Whispr)", text: $newWord)
              .textFieldStyle(.roundedBorder)
              .frame(width: 260)
            
            TextField("Replacement (e.g. Wisper)", text: $newReplacement)
              .textFieldStyle(.roundedBorder)
              .frame(width: 260)
            
            HStack {
              Button("Cancel") {
                isAddingWord = false
                newWord = ""
                newReplacement = ""
              }
              .buttonStyle(.bordered)
              
              Button("Save") {
                if !newWord.isEmpty {
                  let newRemap = WordRemapping(match: newWord, replacement: newReplacement.isEmpty ? "✨" : newReplacement)
                  var current = store.settings.hexSettings.wordRemappings
                  current.insert(newRemap, at: 0)
                  store.send(.settings(.setWordRemappings(current)))
                  
                  mockItems.insert(newWord + (newReplacement.isEmpty ? "" : " → \(newReplacement)"), at: 0)
                  
                  newWord = ""
                  newReplacement = ""
                  isAddingWord = false
                }
              }
              .buttonStyle(.borderedProminent)
            }
          }
          .padding(20)
          .background(Color(nsColor: .windowBackgroundColor))
          .cornerRadius(16)
          .shadow(radius: 10)
        }
      }
    }
  }
}

struct DictionaryPill: View {
  let text: String
  var body: some View {
    Text(text)
      .font(TickFont.labelFunc(12, weight: .medium))
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(Color.primary.opacity(0.02))
      .cornerRadius(8)
      .overlay(
        RoundedRectangle(cornerRadius: 8)
          .stroke(Color.primary.opacity(0.08), lineWidth: 1)
      )
  }
}

// MARK: - Snippets Tab

struct SnippetsTabView: View {
  @State private var selectedTab = 0
  @State private var isBannerVisible = true
  @State private var snippets = [
    Snippet(shortcut: "LinkedIn", content: "https://www.linkedin.com/in/john-doe-9b0139134/"),
    Snippet(shortcut: "intro email", content: "Hey, would love to find some time to chat later..."),
    Snippet(shortcut: "my calendly link", content: "calendly.com/you/invite-name")
  ]
  @State private var isAddingSnippet = false
  @State private var shortcutInput = ""
  @State private var contentInput = ""
  
  struct Snippet: Identifiable, Hashable {
    let id = UUID()
    let shortcut: String
    let content: String
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Snippets")
          .font(TickFont.headingFunc(24, weight: .semibold))
          .foregroundStyle(TickColor.textPrimary)
        Spacer()
        Button(action: { isAddingSnippet = true }) {
          Text("Add new")
            .font(TickFont.labelFunc(13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(TickColor.textPrimary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
      }
      .padding(.bottom, 16)

      HStack {
        CustomSegmentedControl(items: ["All", "Personal", "Shared with team"], selectedIndex: $selectedTab)

        Spacer()

        HStack(spacing: 12) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(TickColor.textSecondary)
          Image(systemName: "arrow.up.arrow.down")
            .foregroundStyle(TickColor.textSecondary)
          Image(systemName: "arrow.clockwise")
            .foregroundStyle(TickColor.textSecondary)
        }
        .font(TickFont.bodyFunc(14))
      }
      .padding(.bottom, 20)
      
      Divider()
        .padding(.bottom, 20)
      
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if isBannerVisible {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Text("The stuff you shouldn't have to re-type.")
                  .font(TickFont.display(24, weight: .semibold))
                Spacer()
                Button(action: { isBannerVisible = false }) {
                  Image(systemName: "xmark")
                    .foregroundStyle(TickColor.textSecondary)
                }
                .buttonStyle(.plain)
              }
              
              Text("Save shortcuts to speak the things you type all the time - emails, links, addresses, bios - anything. **Just speak and Tick expands them instantly,** without retyping or hunting through old messages.")
                .font(TickFont.captionFunc(13))
                .foregroundStyle(TickColor.textSecondary)
                .lineSpacing(4)
                .padding(.trailing, 24)
              
              VStack(alignment: .leading, spacing: 8) {
                SnippetDiagramRow(shortcut: "LinkedIn", content: "https://www.linkedin.com/in/john-doe-9b0139134/")
                SnippetDiagramRow(shortcut: "intro email", content: "Hey, would love to find some time to chat later...")
                SnippetDiagramRow(shortcut: "my calendly link", content: "calendly.com/you/invite-name")
              }
              .padding(.vertical, 8)
              
              Button(action: { isAddingSnippet = true }) {
                Text("Add new snippet")
                  .font(TickFont.labelFunc(12))
                  .foregroundColor(.white)
                  .padding(.horizontal, 16)
                  .padding(.vertical, 8)
                  .background(Color.black)
                  .cornerRadius(8)
              }
              .buttonStyle(.plain)
            }
            .padding(24)
            .background(AppTheme.bannerBackground)
            .cornerRadius(16)
            .overlay(
              RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
            )
            .padding(.bottom, 20)
          }
          
          VStack(alignment: .leading, spacing: 0) {
            ForEach(snippets) { snippet in
              HStack {
                Text(snippet.shortcut)
                  .font(TickFont.labelFunc(13))
                  .foregroundStyle(TickColor.textPrimary)
                
                Image(systemName: "arrow.right")
                  .font(TickFont.captionFunc(10))
                  .foregroundStyle(TickColor.textSecondary)
                
                Text(snippet.content)
                  .font(TickFont.captionFunc(13))
                  .foregroundStyle(TickColor.textSecondary)
                  .lineLimit(1)
                
                Spacer()
                
                Button(action: {
                  NSPasteboard.general.clearContents()
                  NSPasteboard.general.setString(snippet.content, forType: .string)
                }) {
                  Image(systemName: "doc.on.doc")
                    .font(TickFont.captionFunc(11))
                    .foregroundStyle(TickColor.textSecondary)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                  snippets.removeAll { $0.id == snippet.id }
                }) {
                  Image(systemName: "trash")
                    .font(TickFont.captionFunc(11))
                    .foregroundStyle(TickColor.textSecondary)
                    .padding(.leading, 8)
                }
                .buttonStyle(.plain)
              }
              .padding(.vertical, 14)
              .padding(.horizontal, 16)
              
              Divider()
            }
          }
          .background(Color(nsColor: .controlBackgroundColor))
          .cornerRadius(12)
          .overlay(
            RoundedRectangle(cornerRadius: 12)
              .stroke(Color.primary.opacity(0.06), lineWidth: 1)
          )
        }
      }
      
      if isAddingSnippet {
        ZStack {
          Color.black.opacity(0.1)
            .edgesIgnoringSafeArea(.all)
          
          VStack(spacing: 16) {
            Text("Add new snippet shortcut")
              .font(TickFont.headingFunc(15, weight: .bold))
            
            TextField("Shortcut keyword (e.g. LinkedIn)", text: $shortcutInput)
              .textFieldStyle(.roundedBorder)
              .frame(width: 260)
            
            TextField("Expanded content...", text: $contentInput)
              .textFieldStyle(.roundedBorder)
              .frame(width: 260)
            
            HStack {
              Button("Cancel") {
                isAddingSnippet = false
                shortcutInput = ""
                contentInput = ""
              }
              .buttonStyle(.bordered)
              
              Button("Save") {
                if !shortcutInput.isEmpty && !contentInput.isEmpty {
                  snippets.insert(Snippet(shortcut: shortcutInput, content: contentInput), at: 0)
                  shortcutInput = ""
                  contentInput = ""
                  isAddingSnippet = false
                }
              }
              .buttonStyle(.borderedProminent)
            }
          }
          .padding(20)
          .background(Color(nsColor: .windowBackgroundColor))
          .cornerRadius(16)
          .shadow(radius: 10)
        }
      }
    }
  }
}

struct SnippetDiagramRow: View {
  let shortcut: String
  let content: String

  var body: some View {
    HStack(spacing: 8) {
      Text(shortcut)
        .font(TickFont.labelFunc(12, weight: .medium))
        .foregroundStyle(TickColor.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(TickColor.canvas)
        .cornerRadius(8)
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(TickColor.line, lineWidth: 1)
        )

      Image(systemName: "arrow.right")
        .font(TickFont.labelFunc(11, weight: .medium))
        .foregroundStyle(TickColor.textSecondary)

      Text(content)
        .font(TickFont.bodyFunc(12))
        .foregroundStyle(TickColor.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(TickColor.canvas)
        .cornerRadius(8)
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(TickColor.line, lineWidth: 1)
        )
    }
  }
}

// MARK: - Style Tab

struct StyleTabView: View {
  @Shared(.hexSettings) var hexSettings: HexSettings
  @State private var selectedTab = 0
  @Binding var isWizardPresented: Bool
  @AppStorage("hasSeenPersonalisationWizard") private var hasSeenWizard: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Styles")
          .font(TickFont.headingFunc(24, weight: .semibold))
          .foregroundStyle(TickColor.textPrimary)
        Spacer()
      }
      .padding(.bottom, 16)
      
      HStack {
        CustomSegmentedControl(items: ["Personal messages", "Work messages", "Email", "Other"], selectedIndex: Binding(
          get: { selectedTab },
          set: {
            selectedTab = $0
            if $0 == 3 {
              isWizardPresented = true
              selectedTab = 0
            }
          }
        ))
        Spacer()
      }
      .padding(.bottom, 20)
      
      Divider()
        .padding(.bottom, 20)
      
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
              SnapchatIcon()
              MessengerIcon()
              WhatsappIcon()
              TelegramIcon()
              
              VStack(alignment: .leading, spacing: 2) {
                Text("This style applies in the personal messengers")
                  .font(TickFont.labelFunc(14))
                  .foregroundStyle(TickColor.textPrimary)
                Text("Available on desktop in English. iOS and more languages coming soon")
                  .font(TickFont.caption)
                  .foregroundStyle(TickColor.textSecondary)
              }
              Spacer()
            }
          }
          .padding(20)
          .background(AppTheme.bannerBackground)
          .cornerRadius(16)
          .overlay(
            RoundedRectangle(cornerRadius: 16)
              .stroke(Color.primary.opacity(0.04), lineWidth: 1)
          )
          
          HStack(spacing: 16) {
            StylePreviewCard(
              title: "Formal.",
              label: "Caps + Punctuation",
              preview: "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you.",
              avatarColor: Color(red: 220/255, green: 210/255, blue: 255/255),
              isSelected: hexSettings.selectedStyleIndex == 0,
              action: { $hexSettings.withLock { $0.selectedStyleIndex = 0; $0.hasSelectedStyle = true } }
            )
            
            StylePreviewCard(
              title: "Casual",
              label: "Caps + Less punctuation",
              preview: "Hey, are you free for lunch tomorrow? Let's do 12 if that works for you",
              avatarColor: Color(red: 255/255, green: 200/255, blue: 240/255),
              isSelected: hexSettings.selectedStyleIndex == 1,
              action: { $hexSettings.withLock { $0.selectedStyleIndex = 1; $0.hasSelectedStyle = true } }
            )
            
            StylePreviewCard(
              title: "very casual",
              label: "No caps + Less punctuation",
              preview: "hey, are you free for lunch tomorrow? let's do 12 if that works for you",
              avatarColor: Color(red: 100/255, green: 40/255, blue: 180/255),
              isSelected: hexSettings.selectedStyleIndex == 2,
              action: { $hexSettings.withLock { $0.selectedStyleIndex = 2; $0.hasSelectedStyle = true } }
            )
          }
        }
      }
    }
    // Show wizard on first visit to Style tab
    .onAppear {
      if !hasSeenWizard {
        isWizardPresented = true
        hasSeenWizard = true
      }
    }
  }
}

struct StylePreviewCard: View {
  let title: String
  let label: String
  let preview: String
  let avatarColor: Color
  let isSelected: Bool
  let action: () -> Void
  
  @State private var isHovered = false
  
  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 12) {
        Text(title)
          .font(TickFont.display(26, weight: .regular))
          .foregroundStyle(TickColor.textPrimary)
          .padding(.bottom, 2)

        Text(label.uppercased())
          .font(TickFont.eyebrow)
          .tracking(0.6)
          .foregroundStyle(TickColor.textSecondary)
          .padding(.bottom, 12)

        VStack(alignment: .leading, spacing: 8) {
          Text(preview)
            .font(TickFont.bodyFunc(12))
            .foregroundStyle(TickColor.textPrimary)
            .lineSpacing(3)
            .padding(12)
            .background(TickColor.canvas)
            .cornerRadius(12)
        }

        Spacer()

        HStack {
          Spacer()
          Circle()
            .fill(avatarColor)
            .frame(width: 30, height: 30)
            .overlay(
              Text("J")
                .font(TickFont.headingFunc(13, weight: .bold))
                .foregroundColor(avatarColor == Color(red: 100/255, green: 40/255, blue: 180/255) ? .white : TickColor.brand)
            )
        }
      }
      .padding(20)
      .frame(width: 198, height: 260, alignment: .leading)
      .background(Color.white)
      .cornerRadius(16)
      .overlay(
        RoundedRectangle(cornerRadius: 16)
          .stroke(isSelected ? TickColor.brand : (isHovered ? TickColor.lineStrong : TickColor.line), lineWidth: isSelected ? 2 : 1)
      )
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}

// MARK: - App Icon Drawings

struct SnapchatIcon: View {
  var body: some View {
    ZStack {
      Circle()
        .fill(Color(red: 255/255, green: 252/255, blue: 0/255))
        .frame(width: 28, height: 28)
      Image(systemName: "ghost.fill")
        .font(TickFont.bodyFunc(14))
        .foregroundColor(.black)
    }
  }
}

struct MessengerIcon: View {
  var body: some View {
    ZStack {
      Circle()
        .fill(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
        .frame(width: 28, height: 28)
      Image(systemName: "bubble.left.fill")
        .font(TickFont.captionFunc(13))
        .foregroundColor(.white)
    }
  }
}

struct WhatsappIcon: View {
  var body: some View {
    ZStack {
      Circle()
        .fill(Color(red: 37/255, green: 211/255, blue: 102/255))
        .frame(width: 28, height: 28)
      Image(systemName: "phone.fill")
        .font(TickFont.captionFunc(12))
        .foregroundColor(.white)
    }
  }
}

struct TelegramIcon: View {
  var body: some View {
    ZStack {
      Circle()
        .fill(Color(red: 0/255, green: 136/255, blue: 204/255))
        .frame(width: 28, height: 28)
      Image(systemName: "paperplane.fill")
        .font(TickFont.captionFunc(12))
        .foregroundColor(.white)
        .offset(x: -1, y: 0)
    }
  }
}

struct ChatGptIcon: View {
  var body: some View {
    ZStack {
      Circle()
        .fill(Color(red: 16/255, green: 163/255, blue: 127/255))
        .frame(width: 24, height: 24)
      Image(systemName: "sparkles")
        .font(TickFont.captionFunc(11))
        .foregroundColor(.white)
    }
  }
}

struct NotionIcon: View {
  var body: some View {
    ZStack {
      Circle()
        .fill(Color.black)
        .frame(width: 24, height: 24)
      Text("N")
        .font(TickFont.display(12, weight: .black))
        .foregroundColor(.white)
    }
  }
}

struct MediumIcon: View {
  var body: some View {
    ZStack {
      Circle()
        .fill(Color.primary)
        .frame(width: 24, height: 24)
      Circle()
        .fill(Color(nsColor: .windowBackgroundColor))
        .frame(width: 12, height: 12)
    }
  }
}

// MARK: - Notes Tab

struct NotesTabView: View {
  @State private var notes = [
    Note(title: "Project Kickoff Notes", body: "Discussed model requirements, cache locations for Parakeet models on macOS sandbox. Need to complete initial layout by tomorrow.", date: "Today, 10:45 AM"),
    Note(title: "Feature Remappings Idea", body: "Create a list of common regex patterns for clearing background fillers like 'um', 'ah', 'like'. Let users toggle this under settings.", date: "Yesterday, 3:15 PM")
  ]
  @State private var selectedNoteId: UUID?
  
  struct Note: Identifiable {
    let id = UUID()
    var title: String
    var body: String
    let date: String
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Text("Notes")
          .font(TickFont.headingFunc(24, weight: .semibold))
          .foregroundStyle(TickColor.textPrimary)
        Spacer()
        Button(action: {
          let newNote = Note(title: "Untitled Note", body: "", date: "Just now")
          notes.insert(newNote, at: 0)
          selectedNoteId = newNote.id
        }) {
          Label("New Note", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
      
      HStack(alignment: .top, spacing: 16) {
        ScrollView {
          VStack(spacing: 8) {
            ForEach(notes) { note in
              Button(action: { selectedNoteId = note.id }) {
                VStack(alignment: .leading, spacing: 4) {
                  Text(note.title.isEmpty ? "Untitled Note" : note.title)
                    .font(TickFont.labelFunc(13, weight: .medium))
                    .foregroundStyle(TickColor.textPrimary)
                    .lineLimit(1)
                  
                  Text(note.body.isEmpty ? "Empty note" : note.body)
                    .font(TickFont.captionFunc(11))
                    .foregroundStyle(TickColor.textSecondary)
                    .lineLimit(2)
                  
                  Text(note.date)
                    .font(TickFont.captionFunc(9))
                    .foregroundStyle(TickColor.textSecondary)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                  RoundedRectangle(cornerRadius: 8)
                    .fill(selectedNoteId == note.id ? Color.primary.opacity(0.06) : Color.clear)
                )
              }
              .buttonStyle(.plain)
            }
          }
        }
        .frame(width: 180)
        
        Divider()
        
        if let selectedId = selectedNoteId ?? notes.first?.id,
           let index = notes.firstIndex(where: { $0.id == selectedId }) {
          VStack(alignment: .leading, spacing: 16) {
            TextField("Title", text: Binding(
              get: { notes[index].title },
              set: { notes[index].title = $0 }
            ))
            .font(TickFont.labelFunc(18))
            .textFieldStyle(.plain)
            
            TextEditor(text: Binding(
              get: { notes[index].body },
              set: { notes[index].body = $0 }
            ))
            .font(TickFont.captionFunc(13))
            .lineSpacing(4)
          }
          .padding(.leading, 8)
          .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
          VStack {
            Text("No Note Selected")
              .foregroundStyle(TickColor.textSecondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .frame(height: 380)
    }
  }
}

// MARK: - Help Tab

struct HelpTabView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Help & Support")
          .font(TickFont.headingFunc(20, weight: .bold))
        Text("Everything you need to know about setting up and using Tick.")
          .font(TickFont.captionFunc(13))
          .foregroundStyle(TickColor.textSecondary)
      }
      
      VStack(alignment: .leading, spacing: 16) {
        Text("POPULAR FAQS")
          .font(TickFont.headingFunc(10, weight: .bold))
          .foregroundStyle(TickColor.textSecondary)
        
        FAQRow(question: "How do I change the recording hotkey?", answer: "Go to the Settings tab in the sidebar and look for the Hotkey section. Click record and tap the desired keys.")
        FAQRow(question: "Does Tick process audio offline?", answer: "Yes, Tick processes all transcriptions completely offline on your Mac using Core ML, ensuring total privacy.")
        FAQRow(question: "Where are my audio records cached?", answer: "Tick caches models inside your application support container. Legacy files may reside in your local cache directories.")
      }
      .padding(20)
      .background(Color.primary.opacity(0.01))
      .cornerRadius(16)
      .overlay(
        RoundedRectangle(cornerRadius: 16)
          .stroke(Color.primary.opacity(0.04), lineWidth: 1)
      )
    }
  }
}

struct FAQRow: View {
  let question: String
  let answer: String
  @State private var isExpanded = false
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button(action: { withAnimation { isExpanded.toggle() } }) {
        HStack {
          Text(question)
            .font(TickFont.labelFunc(13, weight: .medium))
            .foregroundStyle(TickColor.textPrimary)
          Spacer()
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(TickFont.captionFunc(10))
            .foregroundStyle(TickColor.textSecondary)
        }
      }
      .buttonStyle(.plain)
      
      if isExpanded {
        Text(answer)
          .font(TickFont.captionFunc(12))
          .foregroundStyle(TickColor.textSecondary)
          .padding(.top, 4)
          .transition(.opacity)
      }
      
      Divider()
        .padding(.top, 4)
    }
  }
}

// MARK: - Custom Sidebar Toggle Glyph
//
// A small, custom-drawn icon — two thin parallel lines that subtly hint
// at a side panel. Drawn with shapes instead of an SF Symbol so it doesn't
// read as a stock macOS control. Animates smoothly between the open/closed
// states by shifting the lines outward.
// MARK: - Custom Sidebar Toggle Button
//
// Sits in the title bar area, right beside the green traffic light.
// Draws a minimal custom glyph (two thin bars) and gets a subtle hover
// background. Not a native macOS control — a small Tick-flavoured mark.

struct SidebarToggleButton: View {
  let isOpen: Bool
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      ZStack {
        // Subtle hover background — a soft circle that fades in
        Circle()
          .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
          .frame(width: 22, height: 22)
          .animation(.easeOut(duration: 0.15), value: isHovered)

        // The glyph: two thin vertical bars
        HStack(spacing: isOpen ? 3 : 5) {
          Capsule()
            .fill(Color.primary.opacity(0.7))
            .frame(width: 1.5, height: isOpen ? 10 : 12)
          Capsule()
            .fill(Color.primary.opacity(0.7))
            .frame(width: 1.5, height: isOpen ? 14 : 12)
        }
        .offset(x: isOpen ? 0 : -1)
      }
      .frame(width: 24, height: 24)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isOpen)
  }
}
