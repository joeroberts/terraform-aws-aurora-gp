# Proposal: Standard Aurora Delivery Platform

**Status:** Draft alternative for business and investment review

**Decision requested:** Approve the Aurora module and shared database-access control plane as funded platform work and establish them as the standard path for eligible new Aurora deployments.

**Audience:** Engineering and business leadership, platform leadership, security, finance, and operational stakeholders

## Overview

Application teams need a fast and safe way to deploy Amazon Aurora databases without independently designing networking, security, authentication, availability, backup, monitoring, and recovery controls.

We seek approval to build and adopt:

- An opinionated Aurora Terraform module as the standard application interface.
- A shared database-access control plane that bootstraps and reconciles Identity and Access Management-based permissions.

This document focuses on the business decision, expected outcomes, investment, and operating model. A separate engineering standard describes how this implementation can inform future developer-facing Terraform modules.

## Problem

Aurora is a managed database, but deploying it responsibly still requires many infrastructure decisions. When those decisions are distributed across application teams, the organization pays for the same design work repeatedly and receives inconsistent results.

Current risks include:

- Longer lead time for new databases.
- Repeated platform, security, and architecture reviews.
- Inconsistent authentication and permission practices.
- Uneven production resilience and deletion protection.
- Bespoke implementations that are expensive to upgrade.
- Greater operational burden during recovery and decommissioning.
- Dependence on individual engineers' AWS expertise.

The proposal centralizes reusable decisions while leaving application ownership, data modeling, schema migrations, and workload-specific behavior with the application team.

## Tenets

- The standard path should be the easiest path.
- Security and production protection should be defaults, not optional examples.
- Developers should provide application intent rather than low-level AWS settings.
- Application-owned and platform-owned responsibilities must remain clear.
- Existing organizational observability and backup systems should be reused.
- A platform failure during provisioning must not interrupt existing application traffic.
- Legitimate exceptions require an explicit, reviewable path.

## Requirements

The platform must:

- Support Aurora PostgreSQL and Aurora MySQL.
- Support serverless and provisioned compute.
- Provide simple small, medium, large, and xlarge profiles.
- Adjust availability, backup retention, monitoring, and deletion protection by stage.
- Deploy only into approved private networks.
- Require application-specific encryption.
- Use short-lived Identity and Access Management database authentication for workloads.
- Provide standard runtime, migration, read-only, and monitoring permission levels.
- Work with existing observability and backup platforms.
- Support documented recovery and protected deletion workflows.

### Out of scope

The proposal does not include application schema migrations, a replacement for centralized monitoring or backups, a new virtual private cloud product, global databases, or support for every Aurora feature in the initial release.

## Success criteria

- A standard database can be requested with approximately ten inputs or fewer.
- Eligible applications no longer create or distribute long-lived database passwords.
- At least 80 percent of eligible new Aurora deployments use the standard within two quarters of general availability.
- Deployment lead time and repetitive review effort decline from their pre-launch baselines.
- Production deployments consistently use the approved availability, backup, encryption, and deletion-protection posture.
- Exceptions, failed deployments, and support volume are measured and reviewed.
- Restore and protected-deletion workflows are tested successfully before general availability.

## Architecture

### High-level overview

```text
Application team
      |
      v
Standard Aurora module
      |
      +---- Shared network platform
      +---- Shared database-access control plane
      +---- Existing application identities
      +---- Application-specific encryption key
      |
      v
Amazon Aurora
```

Developers select an engine, stage, compute model, and t-shirt size. The module derives the detailed AWS configuration.

Each deployment represents one application's database permission boundary. The application module manages its Aurora deployment and related application-specific infrastructure. Networking, centralized observability, backup governance, and the database-access service remain shared platform capabilities.

The access-control service uses temporary master-secret access only to create the first Identity and Access Management-authenticated database administrator. It then rotates the master password, removes the temporary access, and uses Identity and Access Management authentication for later permission changes.

The service is not in the application's data path. Existing applications connect directly to Aurora.

## Dependencies

- An approved private network and database subnet group.
- A published network-discovery contract.
- An application-specific encryption key.
- Existing application roles and security groups.
- The proposed shared database-access control plane.
- Existing centralized observability and backup capabilities.
- AWS service availability in each supported account, Region, and compliance environment.

These dependencies require named owners and agreed delivery sequencing before the standard becomes generally available.

## Design alternatives considered

| Alternative | Advantages | Disadvantages |
|---|---|---|
| Teams use the official Aurora module directly | Fastest initial platform path; maximum flexibility | Repeated decisions, uneven controls, and higher long-term support cost |
| Central ticket-based database provisioning | Strong central control | Slow delivery, manual effort, and weak developer autonomy |
| Platform builds Aurora entirely from low-level resources | Maximum control | Duplicates mature upstream work and increases ownership cost |
| Opinionated module over the official module | Combines a small internal contract with mature upstream capability | Requires profile management and a product owner |

The recommended solution is the opinionated module over the official module.

## Cost analysis

### One-time investment

- Design and implementation of the module.
- Design and implementation of the shared database-access control plane.
- Integration with network, encryption, observability, and backup platforms.
- Automated policy and integration tests.
- Security review, operational readiness, documentation, and onboarding.

### Recurring cost

- Workload-specific Aurora capacity and storage.
- Backups, logs, monitoring, encryption-key operations, and Secrets Manager.
- Low-volume shared Lambda and Step Functions execution.
- Platform ownership, release management, support, and periodic integration testing.

### Expected return

- Less application-team design and configuration work.
- Fewer repetitive reviews.
- Lower likelihood of preventable security and resilience gaps.
- Centralized upgrades and policy changes.
- Faster onboarding and recovery.

The implementation team should produce low, expected, and high adoption cost scenarios before final funding is committed. That model should distinguish database workload cost—which exists under any approach—from the incremental platform cost of standardization.

## Failure modes

| Failure | Business impact and response |
|---|---|
| Access-control service is unavailable | New database or permission changes fail; existing applications continue operating |
| Required platform contract is missing | Deployment stops before creating a noncompliant database |
| Bootstrap fails | Temporary access expires and cleanup removes it; deployment reports failure |
| Production deletion is attempted unexpectedly | AWS deletion protection blocks the operation |
| Encryption key is retired too soon | Snapshots can become unrecoverable; key retention must be governed outside database deletion |
| A supported profile is insufficient | The workload uses the exception process or proposes a reusable new profile |

## Non-functional requirements

### Scalability

The shared control plane supports multiple databases and is not duplicated for every application. Database capacity grows through curated t-shirt profiles and Aurora-managed storage.

### Availability and reliability

Development and test prioritize cost efficiency. Staging and production receive multi-Availability-Zone instances, longer retention, deletion protection, and final snapshots.

### Maintainability

The platform team owns module releases, supported profiles, upstream-version promotion, control-plane operations, and documentation. Application teams own data, migrations, workload behavior, and application dependencies.

### Security

Databases remain private and encrypted. Applications use short-lived authentication tokens. Temporary master-secret access is narrow and time-limited. Required controls cannot be silently disabled.

## Testing and observability

The release process will validate:

- PostgreSQL and MySQL.
- Serverless and provisioned compute.
- Development and production policy profiles.
- Permission addition and revocation.
- Snapshot and point-in-time recovery.
- Idempotent updates.
- Disposable development deletion.
- Protected production decommissioning.
- Cleanup after bootstrap failures.

The module produces AWS-native telemetry that existing tools can collect. Platform operations will own dashboards, alerts, paging, and service objectives.

Business-facing reporting should include adoption, deployment lead time, failed-deployment rate, exception rate, support volume, recovery-test results, and estimated engineering time saved.

## Concerns and risks

| Risk | Mitigation |
|---|---|
| Shared control-plane delivery delays the module | Fund and sequence both as one program with separate owners and milestones |
| Low developer adoption | Design for the smallest practical interface and provide onboarding and migration guidance |
| Profiles are too restrictive | Provide a controlled exception path and use recurring exceptions to improve profiles |
| External teams do not publish required contracts | Agree ownership and readiness criteria before general availability |
| The solution becomes Aurora-specific platform debt | Keep the developer-module engineering standard separate and reusable |

## Future improvements

Potential later capabilities include RDS Proxy composition, global-database orchestration, additional workload profiles, and support for further developer-friendly data services.

These capabilities are not required to approve the initial standard and should be justified independently.

## Frequently asked questions

### Why is a shared access-control service necessary?

Terraform can create Aurora infrastructure, but it cannot safely create and maintain engine-native database identities through the AWS provider alone. The shared service performs that work without requiring the Terraform runner to hold the master database credential.

### Will every database need its own service deployment?

No. The service is shared by account, Region, and connected network boundary.

### Will an access-control outage interrupt applications?

No. Existing application connections and Identity and Access Management identities continue to work. New provisioning or permission changes fail until the service recovers.

### Does the proposal replace application migrations?

No. Application teams continue to own database migrations and data-model changes.

### Why not put the encryption key inside the database module?

The key may need to outlive the database so retained snapshots remain recoverable. It also belongs to the application's broader security and retention boundary.

### How will costs be controlled in development?

Development and test default to serverless profiles that can pause when idle, shorter backup and log retention, and a single instance.

## Glossary

- **Aurora:** Amazon's managed relational database compatible with PostgreSQL and MySQL.
- **Control plane:** A shared service that performs database bootstrap and permission reconciliation; it does not carry application query traffic.
- **IAM:** AWS Identity and Access Management.
- **T-shirt size:** A simple capacity choice such as small, medium, large, or xlarge.

## References

- [Authoritative engineering design](../superpowers/specs/2026-08-13-opinionated-aurora-module-design.md)
- [Companion Terraform-module engineering standard](2026-08-13-developer-friendly-terraform-module-engineering-standard.md)
- [System design template used for this document](https://adityarohilla.com/2022/03/22/the-system-design-template-i-use/)
- [Official Terraform Aurora module](https://github.com/terraform-aws-modules/terraform-aws-rds-aurora)
