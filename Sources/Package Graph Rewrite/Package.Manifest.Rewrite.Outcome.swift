public import Package_Graph

extension Package.Manifest.Rewrite {

    /// A manifest after `apply(to:)`, and what was done to it.
    public struct Outcome: Swift.Sendable, Swift.Hashable {

        public let source: Swift.String

        /// The number of `branch: "main"` requirements replaced by the version.
        public let versioned: Swift.Int

        /// The identities of the dependencies removed.
        public let removed: [Swift.String]

        /// The trait requests conditioned, as `dependency.trait`.
        public let conditioned: [Swift.String]

        /// Dependencies on the versioned organizations that are still branch- or revision-based,
        /// for example because their requirement is built outside a `.package(...)` call.
        public let unreached: [Swift.String]

        public init(
            source: Swift.String,
            versioned: Swift.Int,
            removed: [Swift.String],
            conditioned: [Swift.String],
            unreached: [Swift.String]
        ) {
            self.source = source
            self.versioned = versioned
            self.removed = removed
            self.conditioned = conditioned
            self.unreached = unreached
        }
    }
}
