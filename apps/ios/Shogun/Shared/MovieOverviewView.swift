import SwiftUI

struct MovieOverviewView: View {
    let title: String
    let year: String
    let synopsis: String
    var body: some View {
        VStack(alignment: .leading, spacing: ShogunTheme.Spacing.small) {
            Text(title).font(ShogunTheme.Typography.detailTitle)
            Text(year).font(ShogunTheme.Typography.viewIcon).foregroundStyle(ShogunTheme.muted)
            Text(synopsis).foregroundStyle(ShogunTheme.muted)
        }
    }
}

struct CatalogPosterView: View {
    let movie: CatalogMovie
    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: movie.posterURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill().frame(
                        width: geometry.size.width, height: geometry.size.height
                    ).clipped()
                } else {
                    PosterView(movie: movie.placeholder)
                }
            }
        }.aspectRatio(ShogunTheme.Size.posterAspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: ShogunTheme.Radius.poster))
            .accessibilityLabel("Poster for \(movie.title)")
    }
}

struct TMDBAttributionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ShogunTheme.Spacing.small) {
            Image("TMDBLogo").resizable().scaledToFit().frame(width: ShogunTheme.Size.tmdbLogoWidth)
                .accessibilityLabel("The Movie Database")
            Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                .font(ShogunTheme.Typography.footnote).foregroundStyle(ShogunTheme.muted)
            Link("The Movie Database", destination: URL(string: "https://www.themoviedb.org")!)
        }
    }
}

struct MovieResultRow<Artwork: View>: View {
    let title: String
    let year: String
    let isOwned: Bool
    let artwork: Artwork
    var body: some View {
        HStack(spacing: ShogunTheme.Spacing.selector) {
            artwork.frame(width: ShogunTheme.Size.searchPosterWidth)
            VStack(alignment: .leading, spacing: ShogunTheme.Spacing.compact) {
                Text(title).font(ShogunTheme.Typography.headline)
                Text(year).foregroundStyle(ShogunTheme.muted)
                if isOwned {
                    Label("Already owned", systemImage: "checkmark.circle.fill")
                        .font(ShogunTheme.Typography.caption).foregroundStyle(.tint)
                }
            }
        }.padding(.vertical, ShogunTheme.Spacing.tight)
    }
}
