# Standardized Aurora Delivery

**Status:** Draft alternative for stakeholder review

**Decision requested:** Approve the proposed Aurora deployment pattern as the organizational standard, authorize implementation of the application module and shared database-access control plane, and adopt its design tenets as the reference pattern for future developer-facing Terraform modules.

**Audience:** Engineering leadership, platform engineering, security, operations, and application-development teams

## Overview

This document proposes an organization-wide standard for deploying Amazon Aurora databases through Terraform.

We are seeking approval to:

1. Adopt an opinionated Aurora module as the standard deployment path for application teams.
2. Implement the shared database-access control plane required by that module.
3. Use this work as the reference pattern for future developer-friendly Terraform modules.

The proposal does not replace Amazon Aurora, Terraform, or the official community Aurora module. It creates a supported internal product on top of those foundations so application teams can request a secure, operable database without repeatedly making low-level infrastructure decisions.

## Problem

Provisioning a production-ready Aurora database requires decisions across availability, networking, encryption, authentication, monitoring, backups, recovery, upgrades, and deletion protection.

The official community Terraform module provides excellent AWS coverage, but its flexibility exposes many infrastructure-level decisions to every application team. This creates several organizational problems:

- Teams repeatedly solve the same infrastructure problem.
- Security and reliability settings vary between applications.
- Developers need detailed AWS knowledge to provision a database safely.
- Platform reviews become repetitive and difficult to automate.
- Production protection depends on every team selecting the correct options.
- Database credentials and permissions are managed inconsistently.
- Upgrades across bespoke implementations become expensive.
- Shared dependencies and ownership boundaries are often unclear.

The organization needs a supported default that converts application intent into a consistent Aurora deployment.

## Tenets

The Aurora module—and future developer-facing Terraform modules modeled after it—will follow these principles:

- **Developers express intent, not AWS implementation details.**
- **The safest supported configuration is the default.**
- **Common choices use named profiles rather than low-level settings.**
- **Environment and deployment stage have distinct meanings.**
- **Ownership boundaries are explicit.**
- **Existing platform services are discovered through versioned contracts.**
- **Exceptional overrides are narrow, validated, and visible.**
- **Unsupported combinations fail clearly rather than silently weakening controls.**
- **Mature upstream modules are reused rather than reimplemented.**
- **A module is treated as an internal product, not merely a collection of Terraform resources.**

These tenets are intended to create a repeatable way of thinking about developer-facing infrastructure. Aurora is the first concrete application of the pattern, not a one-off exception.

## Requirements

The standard Aurora module must:

- Support Aurora PostgreSQL and Aurora MySQL.
- Support serverless and provisioned compute.
- Use t-shirt sizing for normal capacity selection.
- Derive availability, retention, protection, and monitoring from deployment stage.
- Use private networking supplied by the platform.
- Require an application-specific encryption key owned outside the database module.
- Use AWS Identity and Access Management database authentication for application access.
- Avoid long-lived application database passwords.
- Provide consistent runtime, migration, read-only, and monitoring permission tiers.
- Reconcile database access as part of the Terraform lifecycle.
- Produce vendor-neutral telemetry consumable by Datadog, Grafana/LGTM, Sumo Logic, or other organizational tools.
- Provide explicit recovery and protected decommissioning workflows.
- Preserve clear ownership between the application deployment and shared platform services.

From an application developer's perspective:

- I can request an Aurora database using application identity, deployment context, logical database names, workload identities, and a t-shirt size.
- I receive private, encrypted, stage-appropriate infrastructure without configuring every AWS feature.
- I can choose PostgreSQL or MySQL and serverless or provisioned compute without changing deployment patterns.
- My workload authenticates without a long-lived database password.
- A successful Terraform apply means the requested access has been reconciled and verified.

From a platform and security perspective:

- Mandatory controls are centrally defined, versioned, and tested.
- Shared dependencies are discovered through explicit contracts.
- Exceptions remain visible and limited.
- Existing workloads do not depend on the access-control service for normal database traffic.

### Out of scope

The module will not create:

- Virtual private clouds, subnets, route tables, or NAT gateways.
- Database subnet groups.
- Application Identity and Access Management roles or application security groups.
- Application-specific encryption keys.
- Centralized observability or backup infrastructure.
- RDS Proxy or Aurora Global Database deployments.

It will not run application schema migrations or expose the complete Aurora provider interface as an escape hatch.

## Success criteria

Proposed measures of success are:

- Standard deployments require no more than approximately ten application and platform inputs.
- All eligible deployments use encryption, private networking, Identity and Access Management authentication, backups, and stage-appropriate deletion protection.
- Application teams do not manage long-lived database passwords.
- A developer can request and deploy a standard Aurora database through one documented Terraform workflow.
- At least 80 percent of eligible new Aurora deployments adopt the module within two quarters of general availability.
- Exceptions and unsupported configurations are measurable.
- Median lead time from an approved application change to a ready database decreases.
- Platform support effort per deployment decreases after adoption.
- Module upgrades can be tested and released centrally rather than repeated by every application team.
- The same design tenets are successfully applied to at least one additional developer-facing Terraform module.

Baseline measurements for deployment lead time, review effort, support volume, and configuration exceptions should be captured before general availability.

## Architecture

### High-level overview

```text
Application Terraform
        |
        v
Opinionated Aurora module
        |
        +---- Versioned network contract
        +---- Application-specific encryption key
        +---- Existing workload identities
        +---- Shared database-access control plane
        |
        v
Official Terraform Aurora module
        |
        v
Private, encrypted Amazon Aurora deployment
```

Each Aurora deployment serves one application permission boundary.

The application module owns the database cluster and its application-specific dependencies. Shared services—networking, database-access automation, backup governance, and observability collection—remain independently owned platform capabilities.

The shared database-access control plane bootstraps Identity and Access Management-based database administration once, removes its temporary access, and performs later permission reconciliation without relying on the master credential.

Existing application traffic does not depend on the control plane. A control-plane outage prevents new access changes from completing but does not interrupt an already running database or its existing application identities.

### Developer interface

For the normal case, a developer provides:

- Application name.
- Operating environment, such as commercial or FedRAMP.
- Deployment stage: development, test, staging, or production.
- Database engine.
- Logical database name and, for PostgreSQL, a dedicated schema name.
- Application-specific encryption key.
- Existing workload roles and source security groups.

Serverless compute and a small t-shirt size are the defaults. Stage selects the expected availability, backup retention, deletion protection, monitoring, and change-management posture.

### Component-level responsibilities

**Application Aurora module**

- Translates a small developer contract into the full Aurora configuration.
- Invokes the official Aurora module at a reviewed, pinned version.
- Creates cluster-specific security, logging, monitoring, and parameter resources.
- Applies exact connection permissions to supplied workload roles.
- Calls the shared database-access control plane and waits for verified completion.

**Shared database-access control plane**

- Is deployed once per account, Region, and connected network boundary.
- Uses temporary, time-limited access to bootstrap the first database Identity and Access Management identity.
- Rotates the RDS-managed master password after bootstrap.
- Removes temporary permissions on both success and failure paths.
- Reconciles fixed application permission tiers through Identity and Access Management authentication thereafter.

**Network platform**

- Owns the virtual private cloud, subnets, and database subnet group.
- Publishes a versioned discovery contract.

**Application key owner**

- Owns the application-specific customer-managed encryption key.
- Retains the key as long as any cluster, backup, or snapshot depends on it.

**Central operations platforms**

- Own observability forwarding, dashboards, alerts, backup vaults, regulatory retention, and cross-account or cross-Region recovery copies.

## Dependencies

The solution depends on:

- A versioned network contract published by the network platform.
- An application-specific customer-managed encryption key.
- Existing application Identity and Access Management roles and security groups.
- A shared database-access control plane.
- Central backup and observability services.
- Amazon Aurora, Secrets Manager, CloudWatch, Lambda, and Step Functions availability in each supported environment.

Missing or incompatible dependencies cause deployment to fail explicitly. The application module will not invent, guess, or silently weaken an external contract.

## Design alternatives considered

| Alternative | Benefit | Limitation |
|---|---|---|
| Application teams use the official module directly | Maximum flexibility and minimal platform code | Repeats decisions and produces inconsistent outcomes |
| Platform builds a completely custom Aurora module | Complete implementation control | Duplicates mature upstream work and increases maintenance |
| Opinionated facade over the official module | Small developer contract with upstream capability | Requires deliberate profile and release management |
| Managed database requests through tickets | Central control | Slow delivery, manual operations, and poor developer autonomy |

The recommended approach is an opinionated facade over the official module. It preserves the capability and maintenance investment of the upstream project while providing an organizational contract that is smaller, safer, and testable.

## Cost analysis

The primary implementation investment is engineering time for:

- The Aurora module and automated tests.
- The shared database-access control plane.
- Platform contracts and integration fixtures.
- Documentation, examples, release automation, and operational runbooks.
- Initial security and architecture review.
- Adoption support and migration guidance.

Recurring costs remain primarily workload-driven Aurora costs. Additional shared costs include Lambda, Step Functions, logging, monitoring, encryption-key operations, and Secrets Manager. The control plane is shared, invoked infrequently, and is not expected to be a major cost driver.

The expected return is reduced application-team effort, fewer bespoke implementations, more consistent controls, less repetitive review work, and centralized upgrades.

A detailed dollar forecast depends on the number, size, stage distribution, traffic profile, and retention requirements of expected clusters. Before implementation approval becomes a funding commitment, the platform team should provide a workload model with low, expected, and high adoption scenarios.

## Failure modes

| Failure | Expected behavior |
|---|---|
| Shared control plane is unavailable | Terraform access changes fail; existing workloads continue operating |
| Network contract is missing or malformed | Deployment fails before creating an unsafe cluster |
| Required AWS capability is unavailable | Deployment fails rather than silently disabling the requirement |
| Bootstrap is interrupted | Temporary credential access expires and the cleanup workflow removes it |
| Master-password rotation fails | Bootstrap remains incomplete and can retry through the established Identity and Access Management identity |
| Application encryption key cannot be used | AWS rejects the deployment; no unencrypted fallback is allowed |
| Production deletion is attempted accidentally | Deletion protection rejects the operation |
| A Terraform invocation times out | The durable workflow continues idempotently; a later apply observes or resumes the same operation |

## Non-functional requirements

### Scalability

- The shared control plane supports many application databases without being deployed once per database.
- Database capacity scales through curated t-shirt profiles.
- New profiles are added through reviewed module releases rather than one-off pass-through variables.

### Availability and reliability

- Development and test favor cost efficiency and can use a single instance.
- Staging and production use two instances across Availability Zones.
- Existing application traffic has no runtime dependency on the access-control service.
- Recovery and decommission are explicit, tested workflows.

### Maintainability

- The platform team owns the module contract, profile catalog, releases, and shared control plane.
- Upstream module and engine versions are pinned and promoted through tested releases.
- Shared dependencies use versioned contracts.
- Operational and application responsibilities are documented separately.

### Security

- Databases are private and encrypted.
- Application traffic uses security-group references rather than arbitrary network ranges.
- Application access uses short-lived Identity and Access Management tokens.
- Temporary master-secret access is narrowly scoped, time-limited, and removed after bootstrap.
- Production deletion protection is enabled by default.
- Required controls cannot be silently disabled by callers.

## Testing and observability

Every release will test the engine, stage, compute, and size policy matrix. Cost-bearing integration tests will validate representative PostgreSQL, MySQL, serverless, provisioned, recovery, permission-change, and deletion workflows.

The module will expose operational identifiers and AWS telemetry without prescribing a single external observability provider. Organization-level tools continue to own collection, dashboards, alerts, paging, and service-level objectives.

Operational measures should include:

- Module adoption and exception rates.
- Deployment and reconciliation success rates.
- Deployment duration.
- Access-control workflow failures and cleanup outcomes.
- Aurora availability, failovers, capacity pressure, connections, storage growth, and query performance.
- Backup and restore verification.

## Concerns and risks

| Risk | Mitigation |
|---|---|
| Profiles become too restrictive | Controlled overrides and a documented profile-review process |
| Shared platform dependencies delay application delivery | Versioned contracts, readiness checks, clear ownership, and service objectives |
| External encryption key is removed too early | Key-module protection, governance, and retention ownership outside the database lifecycle |
| Adoption remains low | Small interface, strong examples, migration guidance, and measured developer feedback |
| Upstream changes break compatibility | Exact version pins, automated tests, and reviewed facade releases |
| The reference pattern becomes a rigid universal standard | Apply the tenets to developer-facing modules while allowing evidence-based exceptions |

## Future improvements

Future releases may add separately justified capabilities such as RDS Proxy composition, global-database orchestration, additional profiles, and related developer-friendly data modules.

The platform organization can also use adoption evidence from Aurora to formalize a broader Terraform-module standard.

## Frequently asked questions

### Why not expose the official module directly?

Application teams should select business-relevant outcomes, not repeatedly configure the full Aurora API. The official module remains the implementation foundation.

### Does this prevent advanced use cases?

No. It establishes a supported default. Workloads outside the supported profiles require an explicit architectural review and may justify a reusable new profile.

### Is the shared control plane deployed once per database?

No. It is shared across databases within an account, Region, and connected network boundary. Each database creates only a lightweight target role and lifecycle registration.

### Does the control plane sit in the application data path?

No. Applications connect directly to Aurora. The control plane is used only for bootstrap and permission reconciliation.

### Does this replace database migrations?

No. It manages infrastructure, authentication, and fixed permissions. Application migrations remain application-owned.

### Why is the encryption key outside the Aurora module?

The key may need to outlive the cluster so retained snapshots remain recoverable. Its policy and lifecycle also belong to the broader application security boundary.

### What is meant by a developer-friendly Terraform module?

It is a supported internal product that asks developers for intent, applies organizational policy, exposes stable outcomes, and makes exceptional cases explicit.

## Appendix A: Initial policy profile

- **Engines:** Aurora PostgreSQL and Aurora MySQL.
- **Compute:** serverless by default, with provisioned profiles available.
- **Sizes:** small, medium, large, and xlarge.
- **Availability:** one instance in development and test; two in staging and production.
- **Backup retention:** 1, 3, 14, and 35 days by stage.
- **Deletion protection:** enabled in staging and production.
- **Observability:** AWS-native telemetry designed for external collectors and monitoring platforms.
- **Storage:** Aurora-managed growth; standard or I/O-Optimized storage profiles.

Detailed implementation values and lifecycle contracts are maintained in the authoritative engineering specification.

## Glossary

- **Aurora:** Amazon's managed relational database service compatible with PostgreSQL and MySQL.
- **Facade module:** An internal module that presents a smaller, organization-specific contract over a broader upstream module.
- **IAM:** AWS Identity and Access Management.
- **Permission boundary:** The database, identities, and grants dedicated to one application.
- **Profile:** A named set of tested infrastructure choices.
- **T-shirt size:** A simple capacity choice such as small, medium, large, or xlarge.

## References

- [Authoritative engineering design](../superpowers/specs/2026-08-13-opinionated-aurora-module-design.md)
- [System design template used for this document](https://adityarohilla.com/2022/03/22/the-system-design-template-i-use/)
- [Official Terraform Aurora module](https://github.com/terraform-aws-modules/terraform-aws-rds-aurora)
- [Amazon Aurora documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/CHAP_AuroraOverview.html)
