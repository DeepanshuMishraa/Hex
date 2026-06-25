import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

struct SettingsView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	let microphonePermission: PermissionStatus
	let accessibilityPermission: PermissionStatus
	let inputMonitoringPermission: PermissionStatus

	var body: some View {
		VStack(alignment: .leading, spacing: TickSpacing.xl) {
			// Permissions banner (if needed)
			if microphonePermission != .granted
				|| accessibilityPermission != .granted
				|| inputMonitoringPermission != .granted {
				PermissionsSectionView(
					store: store,
					microphonePermission: microphonePermission,
					accessibilityPermission: accessibilityPermission,
					inputMonitoringPermission: inputMonitoringPermission
				)
			}

			// Model selection
			TickHero {
				VStack(alignment: .leading, spacing: TickSpacing.m) {
					TickEyebrow(text: "Model")
					ModelSectionView(store: store, shouldFlash: store.shouldFlashModelSection)
				}
			}

			// Language (only for WhisperKit)
			if ParakeetModel(rawValue: store.hexSettings.selectedModel) == nil {
				LanguageSectionView(store: store)
			}

			// Hotkey
			HotKeySectionView(store: store)

			// Microphone
			if microphonePermission == .granted && !store.availableInputDevices.isEmpty {
				MicrophoneSelectionSectionView(store: store)
			}

			// Audio
			SoundSectionView(store: store)

			// AI Post-Processing
			AIPostProcessingSectionView(store: store)

			// General
			GeneralSectionView(store: store)

			// History
			HistorySectionView(store: store)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.task {
			await store.send(.task).finish()
		}
		.enableInjection()
	}
}
