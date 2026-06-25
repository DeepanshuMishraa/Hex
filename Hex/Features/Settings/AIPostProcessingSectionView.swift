import ComposableArchitecture
import HexCore
import Inject
import SwiftUI

struct AIPostProcessingSectionView: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<SettingsFeature>
	@State private var apiKeyInput: String = ""
	@State private var showValidationMessage = false
	@State private var validationMessageTimer: Task<Void, Never>?

	var body: some View {
		VStack(alignment: .leading, spacing: TickSpacing.m) {
			TickEyebrow(text: "AI Post-Processing")
				.padding(.leading, TickSpacing.xs)

			VStack(alignment: .leading, spacing: TickSpacing.l) {
				// Cream hero with editorial display
				TickHero {
					VStack(alignment: .leading, spacing: TickSpacing.m) {
						HStack(alignment: .firstTextBaseline) {
							Text("Clean and format transcriptions ")
								.font(TickFont.display(28, weight: .regular))
								.foregroundStyle(TickColor.textPrimary)
							+ Text("with AI")
								.font(TickFont.displayItalic(28))
								.foregroundStyle(TickColor.brand)
						}
						Text("Strips filler words, fixes self-corrections, and adapts tone to the app you're typing in.")
							.font(TickFont.body)
							.foregroundStyle(TickColor.textPrimary)
							.opacity(0.7)
					}
				}

				// Mode + API Key in a card
				VStack(spacing: 0) {
					HStack(alignment: .center, spacing: TickSpacing.l) {
						VStack(alignment: .leading, spacing: 4) {
							Text("MODE".uppercased())
								.font(TickFont.eyebrow)
								.tracking(0.8)
								.foregroundStyle(TickColor.textTertiary)
							Text("Off / On / App-Aware")
								.font(TickFont.body)
								.foregroundStyle(TickColor.textPrimary)
							Text("App-Aware detects the active application and adapts formatting")
								.font(TickFont.caption)
								.foregroundStyle(TickColor.textSecondary)
						}
						Spacer()
						CustomMenuPicker(
							selection: Binding(
								get: { store.hexSettings.aiPostProcessingMode },
								set: { store.send(.setAIPostProcessingMode($0)) }
							),
							options: [
								(.off, "Off", "nosign"),
								(.on, "On", "wand.and.stars"),
								(.appAware, "App-Aware", "app.badge")
							]
						)
					}
					.padding(.vertical, TickSpacing.s)

					if store.hexSettings.aiPostProcessingMode != .off {
						Rectangle().fill(TickColor.line).frame(height: 1)

						VStack(alignment: .leading, spacing: TickSpacing.s) {
							Text("GROQ API KEY")
								.font(TickFont.eyebrow)
								.tracking(0.8)
								.foregroundStyle(TickColor.textTertiary)

							CustomTextField(
								placeholder: "Enter your Groq API key",
								text: $apiKeyInput,
								isSecure: true
							)
							.onChange(of: apiKeyInput) { _, newValue in
								store.send(.setGroqAPIKey(newValue))
							}

							HStack {
								TickPrimaryButton(title: store.isValidatingAPIKey ? "Validating…" : "Validate", icon: "checkmark") {
									store.send(.validateGroqAPIKey)
									showValidationMessage = true
									validationMessageTimer?.cancel()
									validationMessageTimer = Task {
										try? await Task.sleep(for: .seconds(3))
										showValidationMessage = false
									}
								}
								.disabled(apiKeyInput.isEmpty || store.isValidatingAPIKey)

								if showValidationMessage, let status = store.apiKeyValidationStatus {
									HStack(spacing: 4) {
										Image(systemName: status == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
										Text(status == .success ? "Valid" : (status.failureMessage ?? "Invalid"))
									}
									.font(TickFont.caption)
									.foregroundStyle(status == .success ? TickColor.success : TickColor.error)
									.transition(.opacity)
								}
							}

							Text("Uses meta-llama/llama-4-scout-17b-16e-instruct via Groq.")
								.font(TickFont.caption)
								.foregroundStyle(TickColor.textTertiary)
						}
						.padding(.vertical, TickSpacing.s)
					}
				}
				.padding(.horizontal, TickSpacing.l)
				.padding(.vertical, TickSpacing.m)
				.background(
					RoundedRectangle(cornerRadius: TickRadius.card)
						.fill(TickColor.surface)
						.overlay(
							RoundedRectangle(cornerRadius: TickRadius.card)
								.stroke(TickColor.cardBorder, lineWidth: 1)
						)
				)
			}
		}
		.animation(TickAnimation.ease, value: store.hexSettings.aiPostProcessingMode)
		.onAppear {
			apiKeyInput = store.hexSettings.groqAPIKey ?? ""
		}
		.enableInjection()
	}
}

extension SettingsFeature.APIKeyValidationStatus {
	var failureMessage: String? {
		if case .failure(let msg) = self { return msg }
		return nil
	}
}

// MARK: - Custom Text Field (cream background, subtle, no native chrome)

struct CustomTextField: View {
	let placeholder: String
	@Binding var text: String
	var isSecure: Bool = false
	@State private var isHovered = false
	@FocusState private var isFocused: Bool

	var body: some View {
		Group {
			if isSecure {
				SecureField(placeholder, text: $text)
			} else {
				TextField(placeholder, text: $text)
			}
		}
		.font(TickFont.body)
		.padding(.horizontal, TickSpacing.m)
		.padding(.vertical, TickSpacing.s + 2)
		.background(
			RoundedRectangle(cornerRadius: 10)
				.fill(TickColor.canvas)
				.overlay(
					RoundedRectangle(cornerRadius: 10)
						.stroke(isFocused ? TickColor.brand : (isHovered ? TickColor.lineStrong : TickColor.line), lineWidth: 1)
				)
		)
		.foregroundStyle(TickColor.textPrimary)
		.focused($isFocused)
		.onHover { isHovered = $0 }
		.animation(TickAnimation.ease, value: isFocused)
	}
}
