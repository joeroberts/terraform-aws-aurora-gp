# Developer-Friendly Terraform Modules

**Status:** Draft alternative for stakeholder review

**Decision requested:** Adopt an organizational standard for developer-facing Terraform modules, authorize its governance model, and fund the Aurora module and shared database-access control plane as the first reference implementation.

**Audience:** Engineering leadership, platform engineering, architecture, security, operations, and teams that publish or consume internal Terraform modules

## Overview

This document proposes an organizational standard for designing internal Terraform modules. The opinionated Aurora module and its shared database-access control plane will be the first reference implementation.

We are seeking approval to:

1. Adopt these standards for new developer-facing Terraform modules.
2. Implement the Aurora reference module and its required control plane.
3. Establish ownership for reviewing, releasing, and supporting modules built under this standard.

This is not primarily a Terraform coding-style guide. It defines the product, architecture, security, lifecycle, and developer-experience characteristics expected from modules offered as supported platform capabilities.

## Problem

Many Terraform modules are designed as thin wrappers around cloud-provider resources. They expose numerous technical variables but provide little guidance about which combinations are safe, supported, or appropriate.

This transfers platform decisions to every application team and leads to:

- Large, difficult-to-understand module interfaces.
- Inconsistent security and reliability controls.
- Repeated architectural decisions.
- Hidden ownership of shared resources.
- Excessive exceptions and provider-specific knowledge.
- Difficult upgrades and fragmented operational practices.
- Infrastructure that is technically configurable but not developer-friendly.
- Documentation that describes inputs without defining supported outcomes.

Terraform modules intended for internal developers should be treated as products with clear contracts, supported use cases, lifecycle guarantees, and measurable outcomes.

## Tenets

A developer-friendly Terraform module must:

- **Model developer intent rather than mirror provider arguments.**
- **Make the normal case small and safe.**
- **Use profiles for common variation.**
- **Separate application identity, operating environment, deployment stage, and capacity.**
- **State resource ownership explicitly.**
- **Discover shared platform services through versioned contracts.**
- **Reuse mature upstream modules where doing so reduces risk and maintenance.**
- **Pin and test upstream versions.**
- **Offer narrow exceptions without exposing the entire upstream API.**
- **Fail when mandatory capabilities cannot be supplied.**
- **Define stable outputs and lifecycle behavior.**
- **Include recovery, upgrade, and decommission behavior in the initial design.**
- **Remain observable and testable independently of a specific monitoring vendor.**
- **Have a named owner, release process, support model, and deprecation policy.**

These tenets intentionally distinguish an internal product module from a convenience wrapper.

## Requirements

Every qualifying module must document and implement:

- Its target developer and supported use cases.
- Its smallest normal-case input contract.
- Which decisions are explicit and which are derived.
- Stage-derived behavior where operational posture differs by lifecycle stage.
- Resource ownership boundaries.
- Security controls that callers cannot disable.
- Supported profiles and controlled overrides.
- External contracts and dependencies.
- Upgrade and compatibility policy.
- Failure behavior.
- Recovery and decommission procedures.
- Stable outputs and integration points.
- Unit, policy, integration, and release tests.
- Operational ownership and support expectations.

From a developer's perspective:

- I can request a platform capability without becoming an expert in its cloud-provider API.
- The default is suitable for the common production use case.
- Development and test can be cost-conscious without weakening production defaults.
- Errors explain which supported contract was violated.
- Exceptional needs have a documented review path.

From a platform owner's perspective:

- The public contract is intentionally smaller than the underlying provider or upstream module.
- Mandatory organizational controls are testable.
- Upgrades are promoted centrally through reviewed releases.
- Adoption, exceptions, failures, and developer experience can be measured.

### Out of scope

This standard does not require:

- One universal Terraform module.
- Replacing official community modules.
- Eliminating all configuration.
- Supporting every cloud-provider feature.
- Central approval for every normal deployment.
- Forcing all existing modules to migrate immediately.
- A central platform team to own every implementation.

## Success criteria

- New modules have a materially smaller normal-case contract than their underlying providers.
- Required security controls are consistent and testable.
- Teams can provision supported infrastructure without discovering internal platform resource names.
- Modules publish stable outputs and versioned compatibility guarantees.
- Exceptions are explicit and measurable.
- Adoption, deployment lead time, support volume, and policy compliance are tracked.
- At least one reference implementation demonstrates the standard end to end.
- A second module demonstrates that the approach generalizes beyond Aurora.
- Developer feedback shows that normal infrastructure requests require less provider-specific knowledge.

Each module should establish its own product-specific service indicators. Organization-level reporting should include adoption, exception rate, release cadence, failed-deployment rate, support volume, and time to complete a normal deployment.

## Architecture

### High-level pattern

```text
Developer intent
      |
      v
Internal product module
  - profiles
  - policies
  - validation
  - stable outputs
      |
      +---- versioned platform contracts
      +---- externally owned application resources
      |
      v
Official upstream module or cloud provider
      |
      v
Managed infrastructure
```

This layered pattern separates three concerns:

1. The developer describes the desired business capability.
2. The internal module applies organizational policy and supported profiles.
3. The official module or provider implements cloud resources.

The internal module is not required to wrap an upstream module. It should do so when the upstream module is mature, actively maintained, and compatible with the desired contract.

### Public contract design

Inputs should fall into three groups:

**Required application intent**

- Application or workload identity.
- Operating environment.
- Deployment stage.
- Existing application-owned dependencies.
- Product-specific logical names.

**Common profiles**

- T-shirt size.
- Availability or durability class.
- Supported technology choice.
- Cost or performance profile.

**Exceptional operations**

- Recovery.
- Decommission preparation.
- Emergency change scheduling.
- Narrow, validated performance overrides.

The normal path should not contain a generic pass-through map. If many consumers require the same exception, the module owner should evaluate it as a new profile.

### Platform contracts

Modules should not require developers to know opaque shared-resource identifiers. A platform owner publishes a versioned discovery contract, and the consuming module validates it against live provider metadata.

Contracts must include:

- A versioned namespace.
- A minimal payload.
- Clear ownership.
- Compatibility and deprecation rules.
- Validation of account, Region, network, environment, and stage where relevant.

### Ownership model

Every module must classify dependencies as:

- **Owned:** Created and destroyed by the module.
- **Referenced:** Supplied or discovered but never lifecycle-managed by the module.
- **Shared service:** Operated independently and consumed through a versioned contract.

This classification must cover creation, change, recovery, and deletion—not only initial deployment.

## Aurora reference implementation

The first implementation will provide:

- Aurora PostgreSQL and Aurora MySQL.
- Serverless and provisioned compute.
- Stage-derived availability and protection.
- T-shirt sizing.
- Private networking discovered from a platform contract.
- Application-specific external encryption keys.
- Identity and Access Management-based database access.
- A shared access-control service.
- Vendor-neutral telemetry.
- Protected recovery and deletion workflows.

Aurora is a strong reference because it exercises security, networking, identity, lifecycle, recovery, external dependencies, cost profiles, and observability in one bounded module.

## Dependencies

Adopting this standard depends on:

- A governance owner with authority to maintain the standard.
- Platform teams willing to own modules as products.
- A common approach to versioned service discovery.
- Continuous-integration support for Terraform validation and tests.
- Dedicated accounts or environments for cost-bearing integration tests.
- Security, architecture, and operations participation in profile definition.
- Product-management or developer-experience capacity to measure module outcomes.

The Aurora reference implementation additionally depends on the network platform, application encryption keys, application identities, and the proposed database-access control plane.

## Design alternatives considered

| Alternative | Benefit | Limitation |
|---|---|---|
| Let every team design its own modules | Maximum local autonomy | Duplicated effort and inconsistent controls |
| Publish Terraform coding conventions only | Low implementation cost | Does not govern module behavior, lifecycle, or user experience |
| Create one central mega-module | Strong nominal uniformity | Tight coupling, an unmaintainable interface, and weak domain ownership |
| Establish product-oriented standards with reference modules | Consistency with bounded ownership | Requires platform investment and ongoing governance |
| Offer only ticket-based platform services | Central control | Slower feedback, manual work, and poor self-service |

The recommended approach is product-oriented standards with bounded, domain-specific reference modules.

## Cost analysis

The standard creates an upfront platform and governance investment:

- Define and maintain the standard.
- Review module designs and lifecycle contracts.
- Build and operate reference implementations.
- Provide testing infrastructure and release automation.
- Measure adoption and developer experience.
- Maintain documentation, examples, and migration guidance.

Expected benefits include reduced repeated design work, security reviews, application-team toil, configuration drift, and long-term upgrade cost.

The Aurora implementation provides the first opportunity to measure this trade-off using deployment lead time, required input count, adoption, exceptions, support effort, and policy compliance. The standard should be revisited using that evidence before broad mandatory adoption.

## Failure modes

| Failure | Expected response |
|---|---|
| A module mirrors the provider despite passing a checklist | Contract review evaluates the user journey and normal-case input count |
| A profile does not fit a valid workload | Review whether a reusable profile or a documented exception is appropriate |
| A shared contract changes incompatibly | Version the new contract and preserve or explicitly deprecate the old version |
| An upstream release breaks compatibility | Keep the exact pin until automated tests and review approve an upgrade |
| The owning team stops maintaining a module | Trigger the documented transfer, deprecation, or replacement process |
| Governance becomes a bottleneck | Delegate domain ownership and review outcomes rather than implementation details |
| Mandatory control is unavailable | Fail explicitly; do not silently reduce the baseline |

## Non-functional requirements

### Scalability

- Governance must scale through domain ownership, reusable checklists, and automated tests.
- Module contracts must support normal growth without exposing every provider setting.
- Shared platform services must publish capacity and service expectations.

### Availability and reliability

- Modules must define the operational effect of unavailable dependencies.
- Runtime services should avoid unnecessary dependence on provisioning control planes.
- Recovery and deletion behavior must be tested before general availability.

### Maintainability

Each module must have:

- A named owning team.
- A documented compatibility policy.
- Tested, pinned upstream dependencies.
- A release process.
- A support and deprecation policy.
- A mechanism for proposing new profiles or exceptions.
- Usage and exception metrics.

Governance evaluates the public contract and supported outcomes, not every internal implementation detail.

### Security

- Mandatory controls are part of profiles rather than optional examples.
- Secret values and credentials are not normal Terraform outputs.
- External identities and keys have clear owners.
- Modules use least-privilege access and narrow network contracts.
- Unsupported security capabilities fail visibly.

## Testing and observability

Every developer-facing module should include:

- Formatting and validation checks.
- Static analysis and policy tests.
- Native Terraform tests covering the complete profile matrix.
- Negative tests for invalid and unsafe combinations.
- Contract tests for external dependencies.
- Integration tests for representative creation, change, recovery, and deletion workflows.
- Upgrade tests for upstream dependencies.

Module-product metrics should include:

- Adoption.
- Successful and failed deployment rates.
- Deployment duration.
- Exception frequency.
- Support volume and recurring questions.
- Upgrade lag.
- Developer satisfaction with the normal workflow.

## Concerns and risks

| Risk | Mitigation |
|---|---|
| The standard becomes overly prescriptive | Apply it first to new platform-owned modules and allow evidence-based exceptions |
| Review becomes a delivery bottleneck | Delegate decisions to domain owners and automate objective checks |
| Teams satisfy documentation without improving usability | Measure normal-case inputs, deployment time, support volume, and user feedback |
| Shared contracts introduce cross-team dependencies | Define ownership, versioning, compatibility, and service expectations |
| Existing modules diverge for an extended period | Use progressive adoption tied to material redesigns rather than a big-bang migration |
| Central profiles lag workload needs | Use a clear profile-proposal process and monitor exception patterns |

## Future improvements

- Publish reusable templates for module design, tests, documentation, and release automation.
- Establish a catalog of approved versioned platform contracts.
- Add automated conformance checks where requirements are mechanically testable.
- Build a module scorecard based on developer outcomes rather than variable counts alone.
- Use evidence from Aurora and subsequent modules to refine the standard.

## Frequently asked questions

### Is this a Terraform coding standard?

No. It is a product and architecture standard for Terraform modules consumed by developers.

### Must every module wrap a community module?

No. It should reuse mature upstream work when that reduces maintenance without weakening the internal contract.

### Does opinionated mean inflexible?

No. It means normal cases are deliberately easy and exceptional cases are explicit.

### Does this eliminate application-team responsibility?

No. The module owns infrastructure policy within its boundary. Applications still own their code, data model, migrations, usage, and workload-specific operating behavior.

### Does every existing module need to be rewritten?

No. The standard initially applies to new developer-facing modules. Existing modules can adopt it during material redesign or when evidence shows that their current contracts are causing risk or toil.

### Who approves exceptions?

The domain module owner and the relevant architecture or security owner approve exceptions. Repeated exceptions should trigger evaluation of a reusable profile.

### Why begin with Aurora?

Aurora is valuable to application teams and exercises nearly every important module-design concern: security, identity, networking, cost, lifecycle, recovery, observability, and shared-platform integration.

## Appendix A: Module review checklist

Before general availability, reviewers must be able to answer:

- Who is the module for?
- What is the smallest successful configuration?
- Which decisions are derived?
- Which controls are mandatory?
- What does the module own?
- Which external contracts does it consume?
- How are unsupported cases handled?
- What happens during upgrade, recovery, and deletion?
- How is the module tested?
- How will adoption and developer experience be measured?
- Who operates and supports it?

## Glossary

- **Developer-facing module:** A supported Terraform module intended for application-team self-service.
- **Profile:** A named and tested combination of infrastructure choices.
- **Provider:** A Terraform integration that manages resources through an external API.
- **Reference implementation:** The first complete application of the proposed standard, used to validate and refine it.
- **Versioned contract:** A published, compatible interface through which one platform capability discovers or consumes another.

## References

- [Aurora engineering design](../superpowers/specs/2026-08-13-opinionated-aurora-module-design.md)
- [System design template used for this document](https://adityarohilla.com/2022/03/22/the-system-design-template-i-use/)
- [Official Terraform Aurora module](https://github.com/terraform-aws-modules/terraform-aws-rds-aurora)
