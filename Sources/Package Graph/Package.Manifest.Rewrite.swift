extension Package.Manifest {

    /// The edits that take one manifest from branch-based dependencies with root trait unions to
    /// versioned dependencies that request each trait where it is used.
    ///
    /// The plan is derived from the package's evaluation and its trait mismatches; the
    /// `Package Graph Rewrite` module applies it to the manifest's source.
    public struct Rewrite: Swift.Sendable, Swift.Hashable {

        /// The version every `branch: "main"` dependency on `organizations` is required from, as
        /// `.upToNextMinor(from:)`; `nil` leaves requirements as they are.
        public let version: Swift.String?

        /// The GitHub organizations whose dependencies are versioned.
        public let organizations: Swift.Set<Swift.String>

        /// The dependencies to remove: trait requests on dependencies that no target references.
        public let removals: Swift.Set<Swift.String>

        /// For each dependency, the traits whose request to condition on the package's own traits
        /// that guard every use of that dependency.
        public let conditions: [Swift.String: [Swift.String: Swift.Set<Swift.String>]]

        /// Dependencies whose trait requests are mismatches but that test targets use. Removing
        /// them would break the tests, so they are left for a nested test package.
        public let retained: Swift.Set<Swift.String>

        public init(
            version: Swift.String?,
            organizations: Swift.Set<Swift.String>,
            removals: Swift.Set<Swift.String> = [],
            conditions: [Swift.String: [Swift.String: Swift.Set<Swift.String>]] = [:],
            retained: Swift.Set<Swift.String> = []
        ) {
            self.version = version
            self.organizations = organizations
            self.removals = removals
            self.conditions = conditions
            self.retained = retained
        }
    }
}

extension Package.Manifest.Rewrite {

    /// The plan for `evaluation`, from the mismatches `Package.Trait.Mismatch.all(in:)` found in it.
    ///
    /// Dependency identities are lowercased, as SwiftPM compares them.
    public init(
        evaluation: Package.Manifest.Evaluation,
        mismatches: [Package.Trait.Mismatch],
        version: Swift.String?,
        organizations: Swift.Set<Swift.String>
    ) {
        var referenced: Swift.Set<Swift.String> = []
        let local = Swift.Set(evaluation.targets.map(\.name.underlying))
        for target in evaluation.targets {
            for dependency in target.dependencies {
                switch dependency {
                case .product(_, let package):
                    referenced.insert(package.underlying.lowercased())
                case .byName(let name) where !local.contains(name):
                    referenced.insert(name.lowercased())
                case .target, .byName:
                    continue
                }
            }
        }
        var removals: Swift.Set<Swift.String> = []
        var retained: Swift.Set<Swift.String> = []
        var conditions: [Swift.String: [Swift.String: Swift.Set<Swift.String>]] = [:]
        for mismatch in mismatches where mismatch.package == evaluation.name {
            let identity = mismatch.dependency.underlying.lowercased()
            switch mismatch.kind {
            case .unused where referenced.contains(identity):
                retained.insert(identity)
            case .unused:
                removals.insert(identity)
            case .guarded(let guards):
                for trait in mismatch.traits where trait.name != "default" {
                    conditions[identity, default: [:]][trait.name] = guards
                }
            }
        }
        self.init(
            version: version,
            organizations: organizations,
            removals: removals,
            conditions: conditions,
            retained: retained
        )
    }
}
