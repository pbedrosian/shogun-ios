import SwiftUI

/// Original procedural artwork, rendered entirely on-device with native shapes.
struct PosterView: View {
    let movie: Movie
    private var colors: [Color] {
        switch movie.palette {
        case 0: return [.teal, .black]
        case 1: return [.pink, .indigo]
        case 2: return [.indigo, .black]
        case 3: return [.orange, .teal]
        case 4: return [.purple, .blue]
        default: return [.cyan, .blue]
        }
    }
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().stroke(.white.opacity(0.15), lineWidth: 1).frame(width: proxy.size.width * 1.3).offset(x: proxy.size.width * 0.3, y: -30)
                VStack(spacing: 12) {
                    Text("S H O G U N  /  CINEMA").font(.system(size: 8, weight: .semibold)).tracking(1)
                    Spacer(minLength: 0)
                    Image(systemName: movie.symbol).font(.system(size: proxy.size.width * 0.32, weight: .ultraLight))
                    Spacer(minLength: 0)
                    Text(movie.title.uppercased()).font(.system(size: max(12, proxy.size.width * 0.095), weight: .black, design: .serif)).multilineTextAlignment(.center)
                    Text(String(movie.year)).font(.caption2.monospaced()).opacity(0.8)
                }.padding(16).foregroundStyle(.white)
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Locally illustrated poster for \(movie.title)")
    }
}
struct MovieCard: View {
    let movie: Movie
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PosterView(movie: movie)
            Text(movie.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(String(movie.year)).font(.caption).foregroundStyle(.secondary)
        }.foregroundStyle(.primary)
    }
}
