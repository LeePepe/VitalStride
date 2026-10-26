import Foundation

/// Configuration for the privacy-safe Azure Blob telemetry destination.
public struct BlobTelemetryConfiguration: Equatable, Sendable {
    public let endpoint: URL
    public let sas: String

    public init(endpoint: URL, sas: String) {
        self.endpoint = endpoint
        self.sas = sas
    }

    /// Reads the expanded host settings from an Info.plist dictionary.
    public static func resolve(
        from infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> BlobTelemetryConfiguration? {
        guard
            let endpointString = nonEmptyString(infoDictionary["LokiKitBlobEndpoint"]),
            let sas = nonEmptyString(infoDictionary["LokiKitBlobSAS"]),
            let endpoint = URL(string: endpointString),
            isValidEndpoint(endpoint),
            isValidSAS(sas)
        else {
            return nil
        }
        return BlobTelemetryConfiguration(endpoint: endpoint, sas: sas)
    }

    public func blobUploadURL(appName: String, date: Date, batchID: String) -> URL? {
        guard
            Self.isValidSAS(sas),
            let appName = Self.pathSegment(appName),
            let batchID = Self.pathSegment(batchID),
            !appName.isEmpty,
            !batchID.isEmpty
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }

        var url = endpoint
        for component in [appName, String(format: "%04d", year), String(format: "%02d", month),
                           String(format: "%02d", day), "\(batchID).jsonl"] {
            url.appendPathComponent(component)
        }
        guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        urlComponents.percentEncodedQuery = sas.hasPrefix("?") ? String(sas.dropFirst()) : sas
        return urlComponents.url
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$("), !trimmed.contains(")") else { return nil }
        return trimmed
    }

    private static func isValidEndpoint(_ endpoint: URL) -> Bool {
        guard
            let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https",
            components.host != nil,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil
        else {
            return false
        }
        return true
    }

    private static func isValidSAS(_ value: String) -> Bool {
        let query = value.hasPrefix("?") ? String(value.dropFirst()) : value
        guard isSafePercentEncodedQuery(query), query.removingPercentEncoding != nil else {
            return false
        }
        var components = URLComponents()
        components.percentEncodedQuery = query
        guard let items = components.queryItems, !items.isEmpty else { return false }
        return items.contains { $0.name == "sig" && !($0.value ?? "").isEmpty }
    }

    private static func isSafePercentEncodedQuery(_ query: String) -> Bool {
        guard !query.isEmpty else { return false }

        let allowedPunctuation = Set("!$&'()*+,-./:;=?@_~")
        let hexDigits = Set("0123456789abcdefABCDEF")
        let scalars = Array(query.unicodeScalars)
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.value == 0x25 {
                guard index + 2 < scalars.count,
                      hexDigits.contains(Character(scalars[index + 1])),
                      hexDigits.contains(Character(scalars[index + 2])) else {
                    return false
                }
                index += 3
                continue
            }

            guard scalar.isASCII,
                  (scalar.value >= 0x30 && scalar.value <= 0x39)
                    || (scalar.value >= 0x41 && scalar.value <= 0x5A)
                    || (scalar.value >= 0x61 && scalar.value <= 0x7A)
                    || allowedPunctuation.contains(Character(scalar)) else {
                return false
            }
            index += 1
        }
        return true
    }

    private static func pathSegment(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains("\\"),
              trimmed != ".", trimmed != ".." else { return nil }
        return trimmed
    }
}
