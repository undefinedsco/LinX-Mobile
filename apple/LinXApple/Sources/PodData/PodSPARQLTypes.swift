import Foundation

struct SPARQLQueryResponse: Decodable {
    let results: SPARQLResultsContainer
}

struct SPARQLResultsContainer: Decodable {
    let bindings: [[String: SPARQLValue]]
}

struct SPARQLValue: Decodable {
    let type: String
    let value: String
}
