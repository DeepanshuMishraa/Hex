import SwiftUI

struct StarRatingView: View {
	let stars: Int

	init(_ stars: Int) {
		self.stars = stars
	}

	var body: some View {
		HStack(spacing: 2) {
			ForEach(0..<5, id: \.self) { i in
				Image(systemName: i < stars ? "star.fill" : "star")
					.font(TickFont.captionFunc(9))
					.foregroundStyle(i < stars ? Color(nsColor: .systemYellow) : Color(nsColor: .tertiaryLabelColor))
			}
		}
	}
}
