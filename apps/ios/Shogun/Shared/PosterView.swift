import SwiftUI

/// Original local poster placeholders, styled like the Figma collection cards.
struct PosterView: View {
    let movie: Movie
    private var color: Color {
        ShogunTheme.Poster.colors[movie.palette % ShogunTheme.Poster.colors.count]
    }
    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading) {
                Spacer(minLength: 0)
                Text(movie.title.uppercased())
                    .font(ShogunTheme.Poster.titleFont(width: proxy.size.width))
                    .lineLimit(3)
                    .foregroundStyle(ShogunTheme.Poster.titleColor)
            }
            .padding(ShogunTheme.Poster.inset(width: proxy.size.width))
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
            .background(color)
        }
        .aspectRatio(ShogunTheme.Size.posterAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: ShogunTheme.Radius.poster))
        .accessibilityLabel("Poster for \(movie.title)")
    }
}
struct MovieCard: View {
    let movie: Movie
    var compact = false
    var formats: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: ShogunTheme.Spacing.compact) {
            PosterView(movie: movie).accessibilityHidden(true)
            if !compact {
                Text(movie.title)
                    .movieTitleStyle()
                Text(formats ?? String(movie.year))
                    .movieMetadataStyle()
            }
        }
        .foregroundStyle(ShogunTheme.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(movie.title), \(movie.year)\(formats.map { ", " + $0 } ?? "")")
    }
}
