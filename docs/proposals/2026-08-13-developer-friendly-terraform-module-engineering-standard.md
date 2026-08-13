# Standard for Developer-Friendly Terraform Modules

**Status:** Draft alternative for engineering governance review

**Decision requested:** Adopt this standard for new platform-owned, developer-facing Terraform modules, with the Aurora delivery platform as its first reference implementation.

**Audience:** Platform engineering, architecture, security, operations, and teams that publish internal Terraform modules

## Overview

This standard defines how internal Terraform modules should be designed when application developers are their primary consumers.

It is independent of Aurora. The proposed Aurora module will be its first reference implementation. A separate business proposal covers the decision and investment required for that platform capability.

The standard treats developer-facing modules as internal products. It governs their public contracts, supported outcomes, ownership, lifecycle, security, testing, and developer experience—not code formatting or file layout alone.

## Problem

Thin wrappers over Terraform providers often reproduce the cloud API as a long list of variables. They may reduce repeated syntax, but they do not reduce the architectural decisions application teams must make.

This produces modules that are technically reusable but difficult to use safely:

- Developers must understand provider-specific details.
- Security and reliability depend on caller choices.
- Shared-resource ownership is ambiguous.
- Unsupported combinations fail late or degrade silently.
- Recovery and deletion are added after initial delivery.
- Every consumer pays for upstream upgrades and policy changes.

The organization needs a consistent way to distinguish a supported developer platform product from a generic Terraform wrapper.

## Tenets

1. **Express intent, not implementation detail.** The normal interface uses application concepts.
2. **Make safe behavior the default.** Mandatory controls do not depend on documentation examples.
3. **Use profiles for recurring variation.** Common choices are named, tested, and supportable.
4. **Keep the public contract small.** Every required variable needs a developer-facing reason.
5. **Separate context dimensions.** Application, environment, stage, and capacity are not interchangeable.
6. **Define ownership.** Creation and deletion boundaries are part of the interface.
7. **Version shared contracts.** Consumers do not guess shared infrastructure identifiers.
8. **Reuse mature upstream work.** Internal policy does not require rebuilding community modules.
9. **Constrain exceptions.** A generic pass-through API defeats the value of an opinionated module.
10. **Fail visibly.** Required security or operational features cannot silently degrade.
11. **Design the full lifecycle.** Upgrade, recovery, and deletion are first-class behaviors.
12. **Measure the product.** Adoption, failures, exceptions, support demand, and developer experience inform releases.

## Requirements

A compliant developer-facing module must document and implement:

- Target consumers and supported use cases.
- The smallest successful configuration.
- Required intent, common profiles, and exceptional operations.
- Derived policy and non-overridable controls.
- Owned, referenced, and shared resources.
- Versioned external dependencies.
- Stable outputs.
- Unsupported configurations and failure behavior.
- Upgrade and compatibility policy.
- Recovery and decommission behavior.
- Unit, policy, contract, integration, and release tests.
- A named owning team, support model, and deprecation process.
- Product and operational success measures.

### Out of scope

This standard does not:

- Mandate a single module implementation pattern for every domain.
- Require an upstream community module when none is suitable.
- Eliminate all workload-specific choices.
- Require immediate migration of existing modules.
- Transfer application code, data, or migration ownership to the platform team.
- Require a single central team to own all platform modules.

## Success criteria

- Normal module use requires materially fewer choices than the underlying provider.
- Mandatory controls are enforced and covered by automated tests.
- Developers do not need opaque internal resource names for shared services.
- Public outputs remain stable within declared version boundaries.
- Repeated exceptions lead to profile improvements or a documented scope decision.
- Upgrade, recovery, and deletion tests pass before general availability.
- Every generally available module has adoption, failure, exception, and support metrics.
- Evidence from Aurora and at least one additional module validates the standard's usefulness.

## Architecture

### High-level pattern

```text
Developer intent
      |
      v
Domain-owned product module
  - supported profiles
  - organizational policy
  - validation
  - stable outputs
      |
      +---- versioned shared-service contracts
      +---- application-owned dependencies
      |
      v
Official upstream module or provider resources
      |
      v
Managed cloud capability
```

### Public contract

Inputs should be separated into:

**Required intent**

These identify the application, operating context, desired capability, and application-owned dependencies.

**Common profiles**

These represent recurring, tested variation such as engine, t-shirt size, availability class, or cost profile.

**Exceptional operations**

These support infrequent lifecycle needs such as recovery, decommission preparation, or an urgent change window.

A generic arbitrary-options map is not part of the normal contract. New recurring needs should become named profiles with tests and support expectations.

### Ownership

Every dependency belongs to one of three categories:

| Category | Meaning |
|---|---|
| Owned | The module creates, changes, and destroys the resource |
| Referenced | The module consumes the resource but never owns its lifecycle |
| Shared service | Another platform capability owns and publishes a versioned integration contract |

The design must explain what happens to every category during creation, update, recovery, and deletion.

### External contracts

Shared services should publish discoverable, versioned contracts. A consuming module validates the contract against live provider metadata before creating dependent resources.

A contract should define:

- Publisher and consumer ownership.
- Schema version.
- Compatibility and deprecation behavior.
- Account, Region, environment, stage, and network scoping where relevant.
- Failure behavior.
- Service availability and support expectations.

### Upstream dependencies

The module owner may use an official or mature community module when it:

- Is actively maintained.
- Supports the required cloud capabilities.
- Has a compatible release and security posture.
- Reduces implementation and ownership burden.

The internal module pins the upstream version and promotes upgrades through tested releases. The upstream API is not automatically exposed to internal consumers.

## Dependencies

- An architecture owner for this standard.
- Domain teams that own individual modules.
- Terraform testing and release automation.
- Dedicated integration-test environments for cost-bearing services.
- A common method for publishing versioned platform contracts.
- Security and operational participation in profile definition.
- A module catalog with ownership and lifecycle status.

## Design alternatives considered

| Alternative | Benefit | Limitation |
|---|---|---|
| No organizational standard | Maximum team autonomy | Repeated decisions and inconsistent developer experience |
| Code-style and naming rules only | Easy to adopt and automate | Does not address product contract, lifecycle, or security outcomes |
| One centrally owned universal module | Strong central control | Poor domain boundaries and an unsustainable interface |
| Product-oriented standard with domain ownership | Consistency with scalable ownership | Requires governance, measurement, and platform investment |

The recommended approach is a product-oriented standard with domain ownership.

## Cost analysis

Adoption requires investment in:

- Standard ownership and review.
- Module product ownership.
- Automated conformance, policy, and integration testing.
- Documentation and examples.
- Versioned platform contracts.
- Developer feedback and product measurement.

The return should be evaluated through reduced application-team effort, fewer repeated reviews, fewer preventable configuration defects, centralized upgrades, and lower support demand.

The standard should not be justified solely by the number of variables removed. It succeeds only if developers deliver compliant infrastructure faster and the organization can maintain it more consistently.

## Failure modes

| Failure | Response |
|---|---|
| A module passes documentation review but remains difficult to use | Measure the normal user journey, required choices, and support demand |
| Governance slows delivery | Automate objective checks and delegate domain decisions to module owners |
| A profile excludes a legitimate workload | Use the exception process and evaluate a reusable profile |
| A platform contract changes incompatibly | Publish a new version and follow the declared deprecation policy |
| Upstream changes create risk | Retain the tested pin until a reviewed release is ready |
| A module loses its owner | Transfer ownership or begin deprecation; do not leave an unsupported product listed as standard |
| Mandatory behavior is unavailable | Fail explicitly and document the unsupported context |

## Non-functional requirements

### Scalability

- Review scales through domain ownership and automation.
- Profiles absorb recurring needs without making the interface unbounded.
- Shared services publish capacity expectations and avoid unnecessary per-application duplication.

### Availability and reliability

- Runtime paths avoid dependence on provisioning services where possible.
- Dependency failure behavior is explicit.
- Recovery and deletion are tested, not merely documented.

### Maintainability

- Modules have named owners and release cadences.
- Dependencies are pinned and upgrades are automated where practical.
- Public contracts follow semantic versioning or another declared compatibility model.
- Deprecation includes migration guidance and a support timeline.

### Security

- Mandatory controls are built into supported profiles.
- Least privilege is applied to module-created permissions.
- Credentials and secret values are not exposed through normal outputs.
- Network, identity, and encryption ownership is explicit.
- Unsupported security contexts fail rather than degrade.

## Testing and observability

Required test layers are:

- Formatting and static validation.
- Policy and security tests.
- Native Terraform tests for the entire supported profile matrix.
- Negative tests for invalid and unsafe combinations.
- External-contract tests.
- Cost-bearing integration tests for creation, change, recovery, upgrade, and deletion.
- Compatibility tests before promoting upstream releases.

Required product and operational measures are:

- Adoption and active deployments.
- Deployment success rate and duration.
- Exception rate and recurring exception categories.
- Upgrade lag.
- Support volume and common questions.
- Developer satisfaction and time to complete the normal workflow.
- Domain-specific service health and recovery evidence.

## Concerns and risks

| Risk | Mitigation |
|---|---|
| Standardization suppresses useful innovation | Apply outcome-based requirements and allow reviewed alternatives |
| Opinionated profiles are mistaken for universal truth | Document the supported scope and measure exceptions |
| Module interfaces grow indefinitely | Require new inputs to demonstrate broad developer value |
| Shared contracts create organizational coupling | Assign owners, version contracts, and define compatibility expectations |
| Existing modules remain inconsistent | Adopt progressively during material redesigns and prioritize high-risk or high-use modules |

## Future improvements

- A reusable repository template for compliant modules.
- Automated documentation and conformance reports.
- A catalog of versioned platform contracts.
- A module maturity model based on lifecycle and developer outcomes.
- Standard release, deprecation, and migration tooling.

## Frequently asked questions

### Is this a coding standard?

No. Coding standards can support it, but this document governs a module's product contract and operational lifecycle.

### Must modules have very few variables?

They must have a small normal path. Complex lifecycle operations may require additional structured inputs, but complexity should not leak into every deployment.

### Are advanced workloads prohibited?

No. They may use a controlled exception, justify a new profile, or use a different architecture when the module's scope does not fit.

### Who owns a module?

The platform team responsible for the domain owns its contract, releases, support, and deprecation. The architecture owner maintains this cross-domain standard.

### When does the standard apply to an existing module?

Initially, during a material redesign or when the module's current interface creates measurable risk, toil, or support demand.

### How does Aurora demonstrate this standard?

It uses a small intent-based contract, stage-derived policy, t-shirt sizing, explicit ownership, versioned discovery, short-lived authentication, stable outputs, controlled exceptions, and tested recovery and deletion.

## Appendix A: Module review checklist

- Who consumes this module?
- What outcome does it provide?
- What is the smallest successful configuration?
- Which decisions are derived and why?
- Which controls cannot be disabled?
- What does the module own, reference, and consume as a shared service?
- How are external contracts versioned and validated?
- What combinations are supported?
- How do upgrades, recovery, and deletion work?
- What are the stable outputs?
- How is the full profile matrix tested?
- Which integration tests prove the lifecycle?
- How will adoption, failures, exceptions, and developer experience be measured?
- Who owns support and deprecation?

## Glossary

- **Developer-facing module:** A Terraform module intentionally offered as an internal self-service product.
- **Profile:** A named and tested combination of implementation settings.
- **Public contract:** The inputs, outputs, lifecycle behavior, and compatibility guarantees exposed to consumers.
- **Reference implementation:** A concrete implementation used to validate and illustrate a standard.
- **Versioned contract:** A published integration interface with explicit compatibility rules.

## References

- [Companion Aurora business proposal](2026-08-13-standard-aurora-delivery-platform.md)
- [Aurora engineering design](../superpowers/specs/2026-08-13-opinionated-aurora-module-design.md)
- [System design template used for this document](https://adityarohilla.com/2022/03/22/the-system-design-template-i-use/)
