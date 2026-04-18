import Foundation

struct Vault: Equatable {
    let name: String
    let url: URL
}

struct NoteItem: Identifiable, Hashable {
    let url: URL
    let title: String
    let relativePath: String

    var id: URL { url }
}
