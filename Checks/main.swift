import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
let movies = MockCatalog.movies
let libraries = MockCatalog.libraries
check(Set(movies.map(\.id)).count == movies.count, "Movie IDs must be unique")
check(Set(MockCatalog.copies.map(\.id)).count == MockCatalog.copies.count, "Copy IDs must be unique")
for copy in MockCatalog.copies {
    check(movies.contains { $0.id == copy.movieID }, "Orphaned movie reference")
    check(libraries.contains { $0.id == copy.libraryID }, "Orphaned library reference")
}
for membership in MockCatalog.memberships {
    check(libraries.contains { $0.id == membership.libraryID }, "Orphaned membership")
}
check(Set(MockCatalog.copies.map(\.format)) == Set(MovieFormat.allCases), "Demonstrate all formats")
check(MockCatalog.copies.filter { $0.movieID == "jaws-1975" && $0.format == .vhs }.count == 2, "Preserve multiple identical-format copies")
check(Set(MockCatalog.copies.filter { $0.movieID == "arrival-2016" }.map(\.libraryID)).count == 2, "Share metadata across libraries")
print("PASS: stable IDs, references, memberships, all formats, repeated copies, and shared metadata")
let arrivalCopyCount = MockCatalog.copies.filter { $0.movieID == "arrival-2016" }.count
let store = CatalogStore()
let arrival = movies.first { $0.id == "arrival-2016" }!
check(store.libraries.count == 3, "Accessible libraries")
check(store.copies(for: arrival).count == arrivalCopyCount, "Ownership spans accessible libraries")
store.update(arrival, watched: false, rating: 3)
store.selectedLibraryID = "family"
check(store.state(for: arrival).rating == 3 && !store.state(for: arrival).watched, "Personal state follows movie across libraries")
store.update(arrival, rating: 99)
check(store.state(for: arrival).rating == 5, "Clamp ratings")
store.update(arrival, clearRating: true)
check(store.state(for: arrival).rating == nil, "Clear rating")
check(store.copies(for: arrival).count == arrivalCopyCount, "Personal state must not alter ownership")
print("PASS: accessible ownership, personal state across libraries, rating bounds and clearing")
for _ in 0..<10 { store.zoomIn() }
check(store.libraryColumns == 2, "Zoom in stops at two columns")
for _ in 0..<10 { store.zoomOut() }
check(store.libraryColumns == 5, "Zoom out stops at five columns")
store.zoomIn()
check(store.libraryColumns == 4, "Zoom advances one column at a time")
let countBeforeAdd = store.copies.count
check(!store.addCopy(movie: arrival, format: .dvd, libraryID: "inaccessible"), "Reject unknown library")
check(store.copies.count == countBeforeAdd, "Rejected additions preserve copies")
check(store.addCopy(movie: arrival, format: .dvd, libraryID: "family"), "Allow copy in writable library")
check(store.copies.count == countBeforeAdd + 1, "Append an individual owned copy")
check(store.movies(in: "family").filter { $0.id == arrival.id }.count == 1, "Adding a copy preserves one movie card")
print("PASS: zoom bounds, writable-library checks, and copy additions without duplicate metadata")
