import CryptoKit
import Foundation

enum Signature {
    private static let secretKey = "1fp}fdSpYaj>7P;5b|HmTBF;OQmC"

    static func generateSignature(params: [String: Any]) -> (sign: String, time: String) {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let sortedKeys = params.keys.sorted()
        var components = sortedKeys.map { "\($0)=\(params[$0] ?? "")" }
        components.append("time=\(timestamp)")
        components.append("secret_key=\(secretKey)")
        let signString = components.joined(separator: "#")
        let sign = Insecure.MD5.hash(data: Data(signString.utf8)).map { String(format: "%02x", $0) }.joined()
        return (sign, String(timestamp))
    }
}
