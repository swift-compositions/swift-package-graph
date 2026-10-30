extension Package.Trait.Mismatch {

    /// Every mismatch in `evaluations`, in manifest and then dependency order.
    ///
    /// A request is a mismatch when some configuration of the requesting package's traits enables
    /// the request while it enables no use of the dependency. The verdict depends on the requesting
    /// manifest alone. The consequences are read from the dependency's manifest when the workspace
    /// has it.
    public static func all(in evaluations: [Package.Manifest.Evaluation]) -> [Self] {
        var byIdentity: [Swift.String: Package.Manifest.Evaluation] = [:]
        for evaluation in evaluations {
            byIdentity[evaluation.name.underlying.lowercased()] = evaluation
        }
        var mismatches: [Self] = []
        for evaluation in evaluations {
            let uses = Usage(evaluation)
            for dependency in evaluation.dependencies where !dependency.traits.isEmpty {
                let token = dependency.identity.underlying.lowercased()
                let kind: Kind
                let traits: [Package.Dependency.Evaluation.Trait]
                switch uses.guards(of: token) {
                case .none:
                    kind = .unused
                    traits = dependency.traits

                case .some(nil):
                    continue

                case .some(let guards?):
                    kind = .guarded(by: guards)
                    traits = dependency.traits.filter { request in
                        guard let condition = request.condition?.traits else { return true }
                        return condition.contains { uses.closure(of: [$0]).isDisjoint(with: guards) }
                    }
                }
                guard !traits.isEmpty else { continue }
                mismatches.append(
                    Self(
                        package: evaluation.name,
                        dependency: dependency.identity,
                        traits: traits,
                        kind: kind,
                        consequences: byIdentity[token].map { requested in
                            Usage(requested).enabled(by: Swift.Set(traits.map(\.name)))
                        }
                    )
                )
            }
        }
        return mismatches
    }
}

extension Package.Trait.Mismatch {

    /// How one manifest uses its dependencies: from the targets its products build, and under which
    /// of its traits.
    fileprivate struct Usage {

        let evaluation: Package.Manifest.Evaluation

        /// For each dependency identity, the trait conditions of its uses; a `nil` element is an
        /// unconditional use.
        let conditions: [Swift.String: [Swift.Set<Swift.String>?]]

        init(_ evaluation: Package.Manifest.Evaluation) {
            self.evaluation = evaluation
            let targets = Swift.Dictionary(
                evaluation.targets.map { ($0.name.underlying, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var reached: Swift.Set<Swift.String> = []
            var pending = evaluation.products.flatMap { $0.targets.map(\.underlying) }
            while let name = pending.popLast() {
                guard let target = targets[name], reached.insert(name).inserted else { continue }
                for dependency in target.dependencies {
                    switch dependency {
                    case .target(let local):
                        pending.append(local.underlying)
                    case .byName(let local) where targets[local] != nil:
                        pending.append(local)
                    case .product, .byName:
                        continue
                    }
                }
            }
            var conditions: [Swift.String: [Swift.Set<Swift.String>?]] = [:]
            for name in reached {
                guard let target = targets[name] else { continue }
                for dependency in target.dependencies {
                    let token: Swift.String
                    switch dependency {
                    case .product(_, let package):
                        token = package.underlying.lowercased()
                    case .byName(let product) where targets[product] == nil:
                        token = product.lowercased()
                    case .target, .byName:
                        continue
                    }
                    conditions[token, default: []].append(target.conditions[dependency]?.traits)
                }
            }
            self.conditions = conditions
        }

        /// `nil` when no product uses `token`; `.some(nil)` when one uses it unconditionally;
        /// otherwise the traits of which one must be enabled for any use to apply.
        func guards(of token: Swift.String) -> Swift.Set<Swift.String>?? {
            guard let uses = self.conditions[token] else { return nil }
            var guards: Swift.Set<Swift.String> = []
            for use in uses {
                guard let use else { return .some(nil) }
                guards.formUnion(use)
            }
            return .some(guards)
        }

        /// `traits` and every trait they enable, transitively.
        func closure(of traits: Swift.Set<Swift.String>) -> Swift.Set<Swift.String> {
            let enables = Swift.Dictionary(
                self.evaluation.traits.map { ($0.name, $0.enabledTraits) },
                uniquingKeysWith: { first, _ in first }
            )
            var closure: Swift.Set<Swift.String> = []
            var pending = Swift.Array(traits)
            while let trait = pending.popLast() {
                guard closure.insert(trait).inserted else { continue }
                pending.append(contentsOf: enables[trait] ?? [])
            }
            return closure
        }

        /// The dependencies that `requested` requires and the package's defaults do not.
        func enabled(
            by requested: Swift.Set<Swift.String>
        ) -> [Package.Dependency.Evaluation.Identity] {
            let enabled = self.closure(of: requested)
            let defaults = self.closure(of: ["default"])
            return self.evaluation.dependencies.filter { dependency in
                guard case .some(let guards?) = self.guards(of: dependency.identity.underlying.lowercased())
                else { return false }
                return !guards.isDisjoint(with: enabled) && guards.isDisjoint(with: defaults)
            }.map(\.identity)
        }
    }
}
