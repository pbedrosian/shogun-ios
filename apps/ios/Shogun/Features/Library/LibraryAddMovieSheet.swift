import SwiftUI

struct LibraryAddMovieSheet: View {
    @Environment(\.movieDiscovery) private var discovery
    var body: some View {
        if let discovery { ConnectedAddMovieSheet(discovery: discovery) }
    }
}
