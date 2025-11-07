import Foundation

struct HTTPResponse {
    let code: Int
    let message: String
    let data: [String: Any]
    let timestamp: Int64?
    let success: Bool?
}

class HTTPClient {
    static let shared = HTTPClient()

    private let session: URLSession

    private var baseURL: String {
        "https://\(Config.shared.SERVER)/api/v1"
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        session = URLSession(configuration: config, delegate: InsecureSSLDelegate(), delegateQueue: nil)
    }

    func post(path: String, body: [String: Any]) async throws -> HTTPResponse {
        let (sign, time) = Signature.generateSignature(params: body)
        
        var signedBody = body
        signedBody["sign"] = sign
        signedBody["time"] = time
        
        guard let url = URL(string: baseURL + path) else {
            throw HTTPError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.shared.AUTH_TOKEN)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: signedBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw HTTPError.statusCode(httpResponse.statusCode)
        }
        
        if let responseString = String(data: data, encoding: .utf8) {
            log.info("POST \(path) Response: \(responseString)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? Int,
              let message = json["message"] as? String,
              let dataDict = json["data"] as? [String: Any] else {
            throw HTTPError.invalidJSON
        }
        
        return HTTPResponse(
            code: code,
            message: message,
            data: dataDict,
            timestamp: json["timestamp"] as? Int64,
            success: json["success"] as? Bool
        )
    }
}

enum HTTPError: Error {
    case invalidURL
    case invalidResponse
    case statusCode(Int)
    case invalidJSON
}

private class InsecureSSLDelegate: NSObject, URLSessionDelegate {
    func urlSession(_: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust
        {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
