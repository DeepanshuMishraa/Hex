import ComposableArchitecture
import Inject
import SwiftUI

struct CuratedList: View {
	@ObserveInjection var inject
	@Bindable var store: StoreOf<ModelDownloadFeature>

	private var visibleModels: [CuratedModelInfo] {
		if store.showAllModels {
			return Array(store.curatedModels)
		} else {
			return store.curatedModels.filter { $0.isParakeet }
		}
	}

	private var hiddenModels: [CuratedModelInfo] {
		store.curatedModels.filter { !$0.isParakeet }
	}

	var body: some View {
		VStack(alignment: .leading, spacing: TickSpacing.s) {
			ForEach(visibleModels) { model in
				CuratedRow(store: store, model: model)
			}

			if !hiddenModels.isEmpty {
				Button(action: { store.send(.toggleModelDisplay) }) {
					HStack(spacing: TickSpacing.xs) {
						Image(systemName: store.showAllModels ? "chevron.up" : "chevron.down")
							.font(TickFont.headingFunc(10, weight: .bold))
						Text(store.showAllModels ? "Show Less" : "Show More Models")
							.font(TickFont.caption)
					}
					.foregroundStyle(TickColor.textTertiary)
					.padding(.vertical, TickSpacing.s)
					.frame(maxWidth: .infinity)
				}
				.buttonStyle(.plain)
			}
		}
		.enableInjection()
	}
}
