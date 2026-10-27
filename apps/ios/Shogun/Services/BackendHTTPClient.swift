import Foundation

struct BackendHTTPError: Error {
    let status: Int
    let code: String?
}

/// Shared HTTP construction; feature services translate transport failures into their own errors.
struct BackendHTTPClient {
    let config: AuthConfiguration
    let session: URLSession
    func post(path: String, body: Data, token: String) async throws -> Data {
        try await send(path: path, method: "POST", body: body, token: token)
    }
    func send(path: String, method: String, body: Data?, token: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: config.url.appendingPathComponent("/")) else {
            throw SignInFailure.configuration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(config.key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if method == "POST" {
            request.httpBody = body ?? Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SignInFailure.unavailable }
        guard (200..<300).contains(response.statusCode) else {
            struct Failure: Decodable { let error: String? }
            let code = try? JSONDecoder().decode(Failure.self, from: data).error
            throw BackendHTTPError(status: response.statusCode, code: code)
        }
        return data
    }
}

/// A fresh account-bound token is obtained for each call, including every pagination request.
@MainActor struct AuthenticatedBackendClient {
    let http: BackendHTTPClient
    let token: @MainActor () async throws -> String
    func rpc(_ name: String, body: Data) async throws -> Data {
        try await http.post(path: "rest/v1/rpc/\(name)", body: body, token: token())
    }
    func function(_ name: String, body: Data) async throws -> Data {
        try await http.post(path: "functions/v1/\(name)", body: body, token: token())
    }
}
