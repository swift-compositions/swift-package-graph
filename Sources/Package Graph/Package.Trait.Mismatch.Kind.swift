extension Package.Trait.Mismatch {

    public enum Kind: Swift.Sendable, Swift.Hashable {

        /// No target that a product of the package builds uses a product of the dependency.
        case unused

        /// Every use of the dependency is conditioned on one of `traits` of the package, and the
        /// request is not.
        case guarded(by: Swift.Set<Swift.String>)
    }
}
