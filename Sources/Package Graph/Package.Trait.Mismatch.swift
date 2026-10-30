extension Package.Trait {

    /// A trait request that SwiftPM's workspace applies but its dependency resolver never sees.
    ///
    /// The workspace enables the traits a package requests on every dependency it declares. The
    /// resolver only follows the dependencies that a product of the package uses under its enabled
    /// traits. When the two disagree, a dependency that the requested traits guard can be required
    /// but never fetched, and resolution fails with "exhausted attempts to resolve the dependencies
    /// graph" (swiftlang/swift-package-manager#10749).
    public struct Mismatch: Swift.Sendable, Swift.Hashable {

        /// The package that makes the requests.
        public let package: Package.Name

        /// The identity of the dependency the traits are requested of.
        public let dependency: Package.Dependency.Evaluation.Identity

        /// The requests that can apply while no use of the dependency does.
        public let traits: [Package.Dependency.Evaluation.Trait]

        public let kind: Kind

        /// The dependencies of `dependency` that only the requested traits require, and that
        /// resolution would therefore miss; `nil` when `dependency`'s manifest is not in the
        /// workspace.
        public let consequences: [Package.Dependency.Evaluation.Identity]?

        public init(
            package: Package.Name,
            dependency: Package.Dependency.Evaluation.Identity,
            traits: [Package.Dependency.Evaluation.Trait],
            kind: Kind,
            consequences: [Package.Dependency.Evaluation.Identity]?
        ) {
            self.package = package
            self.dependency = dependency
            self.traits = traits
            self.kind = kind
            self.consequences = consequences
        }
    }
}
