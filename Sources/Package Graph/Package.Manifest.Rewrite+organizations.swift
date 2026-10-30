extension Package.Manifest.Rewrite {

    /// The organizations in `json`, the one-line array of names that `institute organizations`
    /// prints, for example `["swift-atoms","swift-molecules"]`; `nil` when `json` is not such an
    /// array or names no organization.
    ///
    /// The organizations come from the Institute's roster rather than from this package, which
    /// sits in the compositions layer and must not depend on the Institute's control tooling.
    public static func organizations(parsing json: Swift.String) -> Swift.Set<Swift.String>? {
        let text = json.trimmingWhitespace()
        guard text.first == "[", text.last == "]" else { return nil }
        let body = text.dropFirst().dropLast().trimmingWhitespace()
        guard !body.isEmpty else { return nil }
        var organizations: Swift.Set<Swift.String> = []
        for element in body.split(separator: ",", omittingEmptySubsequences: false) {
            let quoted = Swift.String(element).trimmingWhitespace()
            guard quoted.count >= 2, quoted.first == "\"", quoted.last == "\"" else { return nil }
            let name = quoted.dropFirst().dropLast()
            guard !name.isEmpty,
                name.allSatisfy({ ($0.isLetter && $0.isLowercase) || $0.isNumber || $0 == "-" })
            else { return nil }
            organizations.insert(Swift.String(name))
        }
        return organizations
    }
}

extension Swift.StringProtocol {

    fileprivate func trimmingWhitespace() -> Swift.String {
        Swift.String(self.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    }
}
