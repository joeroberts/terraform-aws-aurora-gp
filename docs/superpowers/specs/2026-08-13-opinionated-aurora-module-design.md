# Opinionated Aurora Module Design

**Date:** 2026-08-13

**Status:** Approved design

**Audience:** Platform engineers implementing and operating the module; application teams consuming it

## Summary

This repository will provide one opinionated Terraform facade for an Amazon Aurora deployment that represents one application's database permission boundary.

The facade wraps the official `terraform-aws-modules/rds-aurora/aws` module and intentionally exposes a much smaller contract. Application teams provide application identity, deployment context, logical database names, network source security groups, existing IAM workload roles, and an externally managed application-specific KMS key. The module derives or discovers the rest.

The module supports Aurora PostgreSQL and Aurora MySQL, as well as Aurora serverless and provisioned compute, without splitting them into separate public modules. Engine, stage, compute mode, and t-shirt size select curated internal profiles.

The module does not create general networking, application IAM identities, the application KMS key, RDS Proxy, centralized backup infrastructure, vendor-specific observability infrastructure, or an Aurora Global Database.

## Goals

- Give application developers a small, stable Terraform API.
- Default to a secure, operable deployment without requiring callers to understand every Aurora setting.
- Support both Aurora PostgreSQL and Aurora MySQL in one public module.
- Support both Aurora serverless and provisioned compute in one public module.
- Use stage to derive availability, protection, observability, and change-management posture.
- Use t-shirt sizing instead of exposing raw capacity knobs in the normal path.
- Require IAM database authentication for application, migration, read-only, monitoring, and ongoing reconciliation identities.
- Bootstrap the database once with the RDS-managed master credential, immediately rotate it, then perform ongoing reconciliation through IAM authentication.
- Keep VPC and shared platform dependencies outside this module and discover them through explicit, versioned contracts.
- Produce vendor-neutral AWS telemetry while allowing organization-level tools such as Datadog, Grafana/LGTM, or Sumo Logic to own collection and alerting.
- Make recovery and decommissioning explicit operational workflows.

## Non-goals

Version 1 will not:

- Create a VPC, NAT gateway, route table, subnet, or DB subnet group.
- Create the application-specific KMS key.
- Create application runtime, migration, read-only, or monitoring IAM roles.
- Create application security groups.
- Create the shared database-access dispatcher, Step Functions workflows, workers, queues, or control-plane datastore.
- Create RDS Proxy.
- Create an Aurora Global Database or manage multi-Region failover.
- Create AWS Backup plans, vaults, vault locks, cross-account copies, or cross-Region copies.
- Create Datadog forwarders, Grafana Alloy, Loki pipelines, Sumo Logic collectors, dashboards, alerts, paging routes, or SLOs.
- Copy, share, or re-encrypt snapshots across accounts or Regions.
- Run application schema migrations.
- Expose arbitrary database grants, arbitrary Aurora parameters, arbitrary CIDR ingress, or the complete upstream module API.
- Manage multiple application permission boundaries in one Aurora deployment.
- Use CloudFormation, local provisioners, the AWS CLI, or direct database providers from the Terraform runner.

## Design principles

1. **One deployment, one application boundary.** A deployment can contain one PostgreSQL database and its application schema, or one MySQL database. It is not a shared database platform for unrelated applications.
2. **Profiles over pass-through variables.** Common choices are named and curated. Exceptional overrides are narrow and validated.
3. **Explicit external contracts.** Shared infrastructure is discovered through versioned SSM parameters and validated against live AWS metadata.
4. **No long-lived application passwords.** Workloads use short-lived IAM authentication tokens.
5. **Synchronous readiness.** A successful Terraform apply means the database access contract was reconciled and IAM authentication was verified.
6. **No silent degradation.** If a mandatory security or operability feature is unavailable for an engine, version, partition, or Region, planning or applying fails with an actionable error.
7. **Data keys outlive databases.** The application KMS key is owned outside this module so snapshots can remain recoverable after the cluster is destroyed.

## Technology baseline

The initial implementation will use:

- Terraform `>= 1.11.1, < 2.0`
- HashiCorp AWS provider `>= 6.54, < 7.0`
- HashiCorp Random provider `>= 3.6, < 4.0`, used only for a state-stable final-snapshot suffix
- Official Aurora module `terraform-aws-modules/rds-aurora/aws` pinned exactly to `10.3.1`, the latest release available on the design date

The upstream module pin is advanced only in a reviewed release of this facade. Provider constraints declare compatibility; the root module remains responsible for selecting a concrete provider version in its lock file.

## Public module contract

### Normal usage

Aurora PostgreSQL is the default engine and Aurora serverless is the default compute mode.

```hcl
module "database" {
  source = "..."

  name          = "orders"
  environment   = "commercial"
  stage         = "prod"
  database_name = "ordersdb"
  schema_name   = "orders"
  kms_key_arn   = module.orders_kms.key_arn

  allowed_security_group_ids = [
    aws_security_group.orders_service.id
  ]

  runtime_role_arns = [
    aws_iam_role.orders_service.arn
  ]

  migrator_role_arns = [
    aws_iam_role.orders_migrations.arn
  ]
}
```

MySQL does not accept a separate schema name because MySQL treats `DATABASE` and `SCHEMA` as synonyms.

```hcl
module "database" {
  source = "..."

  name          = "orders"
  environment   = "commercial"
  stage         = "prod"
  engine        = "mysql"
  database_name = "ordersdb"
  kms_key_arn   = module.orders_kms.key_arn

  allowed_security_group_ids = [aws_security_group.orders_service.id]
  runtime_role_arns           = [aws_iam_role.orders_service.arn]
  migrator_role_arns          = [aws_iam_role.orders_migrations.arn]
}
```

### Required inputs

| Input | Meaning |
|---|---|
| `name` | Application identity used for AWS resource names and canonical tags. |
| `environment` | Operating or compliance boundary, such as `commercial`, `gov`, or `fedramp`. It is not a deployment stage. |
| `stage` | One of `dev`, `test`, `staging`, or `prod`. |
| `database_name` | Explicit logical database name for either engine. |
| `schema_name` | Required for PostgreSQL and prohibited for MySQL. |
| `kms_key_arn` | Externally managed, application-specific customer-managed KMS key. |
| `allowed_security_group_ids` | Existing application source security groups allowed to connect on the engine port. |
| `runtime_role_arns` | Existing same-account IAM roles that receive runtime database access. |
| `migrator_role_arns` | Existing same-account IAM roles that receive migration access. |

`database_name` and `schema_name` are not inferred from `name`. They are explicit because they are durable logical data identities, while `name` is the AWS/application deployment identity.

### Common optional inputs

| Input | Default | Allowed values or meaning |
|---|---:|---|
| `engine` | `postgresql` | `postgresql` or `mysql` |
| `compute_mode` | `serverless` | `serverless` or `provisioned` |
| `size` | `small` | `small`, `medium`, `large`, or `xlarge` |
| `storage_mode` | `standard` | `standard` or `io-optimized` |
| `readonly_role_arns` | `[]` | Existing same-account IAM roles with read-only access. |
| `monitor_role_arns` | `[]` | Existing same-account IAM roles used by direct database monitoring agents. |
| `tags` | `{}` | Additional non-canonical tags. |

### Exceptional operational inputs

| Input | Purpose |
|---|---|
| `engine_version` | Select a controlled, profile-compatible engine version rather than the facade default. |
| `database_insights_mode` | Opt in to `advanced`; defaults to `standard`. |
| `apply_immediately` | Override the stage-derived change schedule for an urgent operation. |
| `provisioned_instance_class` | Override a curated provisioned class for a specialized workload or Region. |
| `recovery` | Create a new cluster from a snapshot or point-in-time source. |
| `decommission` | Prepare a protected staging or production cluster for removal by disabling deletion protection. |

There is no arbitrary parameter map, arbitrary grant map, or raw upstream-module input escape hatch in version 1.

### Identifier validation

- Logical database and schema identifiers are normalized lowercase, unquoted identifiers.
- PostgreSQL `database_name` and `schema_name` must satisfy PostgreSQL identifier constraints and must not be reserved names.
- MySQL `database_name` must satisfy MySQL identifier constraints and must not be a reserved name.
- Supplying `schema_name` for MySQL is an error rather than an ignored value.
- Canonical AWS names are deterministic, partition-aware, and kept within AWS length limits.

## Stage policy

`stage` controls operational posture. `environment` selects an operating boundary and discovery namespace but never weakens the baseline.

| Policy | dev | test | staging | prod |
|---|---:|---:|---:|---:|
| Aurora instances | 1 | 1 | 2 | 2 |
| Backup retention | 1 day | 3 days | 14 days | 35 days |
| Deletion protection | off | off | on | on |
| Final snapshot on delete | no | no | required | required |
| Ordinary changes | immediate | immediate | maintenance window | maintenance window |
| Enhanced Monitoring | 60 seconds | 60 seconds | 15 seconds | 15 seconds |
| Database Insights | standard | standard | standard | standard |
| CloudWatch log retention | 7 days | 14 days | 30 days | 90 days |
| Slow-query threshold | 1 second | 1 second | 500 ms | 500 ms |
| DDL and role audit logging | reduced noise | enabled | enabled | enabled |

Staging and production instances are placed in distinct Availability Zones selected deterministically from the validated subnet group.

Database Insights Advanced is a paid, explicit opt-in. The facade does not automatically duplicate database observability capabilities already purchased from another provider.

## Compute profiles

### Aurora serverless

Maximum capacity is size-derived:

| Size | Maximum ACUs |
|---|---:|
| `small` | 8 |
| `medium` | 16 |
| `large` | 32 |
| `xlarge` | 64 |

Minimum capacity is stage- and size-derived:

| Stage | Minimum ACUs | Auto-pause | Instances |
|---|---|---:|---:|
| `dev` | 0 | 15 minutes | 1 |
| `test` | 0 | 30 minutes | 1 |
| `staging` | 1 / 2 / 4 / 8 by size | disabled | 2 |
| `prod` | 2 / 4 / 8 / 16 by size | disabled | 2 |

Each serverless instance uses the cluster capacity range independently. The pinned engine profiles must support scale-to-zero before dev or test can use it.

### Provisioned

| Size | dev/test | staging/prod |
|---|---|---|
| `small` | `db.t4g.medium` | `db.r7g.large` |
| `medium` | `db.r7g.large` | `db.r7g.xlarge` |
| `large` | `db.r7g.xlarge` | `db.r7g.2xlarge` |
| `xlarge` | `db.r7g.2xlarge` | `db.r7g.4xlarge` |

The implementation uses partition-aware fallback profiles, including broadly available `t3` and `r6g` equivalents where newer Graviton families are unavailable. It validates the chosen class, engine version, storage mode, and Region with `aws_rds_orderable_db_instance`; it does not silently float to a newly released class.

Aurora storage is shared, distributed, and automatically grows. The facade does not expose allocated storage, disk type, IOPS, or throughput. `storage_mode = "io-optimized"` maps to `aurora-iopt1`; otherwise Aurora standard storage is used.

## Engine profiles

| Setting | PostgreSQL | MySQL |
|---|---|---|
| AWS engine | `aurora-postgresql` | `aurora-mysql` |
| Initial RDS API engine version | `17.9` | `8.4.mysql_aurora.8.4.7` |
| Aurora release represented | PostgreSQL 17.9, current patch 17.9.2 | MySQL 8.4.7 |
| Parameter family | `aurora-postgresql17` | `aurora-mysql8.4` |
| Port | 5432 | 3306 |
| TLS enforcement | `rds.force_ssl = 1` | `require_secure_transport = ON` |
| Query telemetry | `pg_stat_statements` | Performance Schema |
| Base log exports | `postgresql`, `iam-db-auth-error` | `audit`, `error`, `slowquery`, `iam-db-auth-error` |

The PostgreSQL profile deliberately remains on major version 17 until the AWS IAM database-authentication support matrix includes PostgreSQL 18. MySQL uses the current Aurora MySQL 8.4 LTS line.

Both profiles:

- Require TLS rather than merely making TLS available.
- Enable IAM database authentication.
- Enable the engine's query-statistics facilities for external database monitoring agents.
- Use wrapper-owned cluster and instance parameter groups.
- Configure stage-derived slow-query logging.
- For PostgreSQL, preload `pg_stat_statements` and `pgaudit`; reconciliation creates the extensions in the application database. `pgaudit` records role and DDL changes outside dev, while native PostgreSQL settings record connections, authentication failures, lock waits, and threshold-based slow statements.
- For MySQL, enable Performance Schema and Advanced Auditing for connection, DDL, and DCL events outside dev; the slow-query log records only statements over the stage threshold.
- Avoid general/all-statement logging in either engine.
- Export supported logs to KMS-encrypted CloudWatch log groups.
- Disable opt-in automatic minor-version advancement.

The facade pins the exact engine-version value accepted by the RDS API. Aurora can still apply mandatory system patches within a selected PostgreSQL minor line, so `17.9.2` is a tested Aurora patch baseline rather than a Terraform-selectable engine version. An engine override is accepted only when it remains compatible with a tested facade profile. Supporting a new major version requires a facade release that defines its parameter family and feature compatibility; setting an arbitrary major version is not a bypass.

If a mandatory baseline feature is unavailable in a target partition or Region, the module fails rather than silently disabling it. For example, an engine/partition combination that cannot publish required authentication logs is unsupported until AWS supplies that capability or the facade explicitly revises its baseline.

## Networking contract

The module does not accept a DB subnet-group name from application developers. The network stack publishes one versioned SSM parameter.

Path:

```text
/platform/network/v1/<environment>/<stage>/<region>/aurora
```

Value:

```json
{
  "schema_version": 1,
  "db_subnet_group_name": "commercial-prod-use1-aurora"
}
```

The module reads the live `aws_db_subnet_group` and derives:

- VPC ID
- Subnet IDs
- Availability Zones
- Subnet-group status
- Tags

It validates that:

- The contract schema version is supported.
- The subnet group exists and has status `Complete`.
- At least two Availability Zones are represented.
- Canonical `Environment`, `Stage`, and `Purpose=aurora` tags match the requested deployment.

The VPC ID is not duplicated in SSM. The live DB subnet group is the VPC source of truth.

## Shared database-access control-plane contract

After deriving the VPC ID, the module discovers a shared control plane deployed once per account, Region, and connected network boundary.

Path:

```text
/platform/database-access/v1/<environment>/<region>/<vpc-id>/control-plane
```

Value:

```json
{
  "schema_version": 1,
  "dispatcher_function_name": "database-access-dispatcher",
  "dispatcher_qualifier": "live",
  "target_role_principal_arn": "arn:aws:iam::123456789012:role/database-access-worker",
  "revision": "2026-08-01.1",
  "security_group_id": "sg-0123456789abcdef0"
}
```

The module validates the schema version, account, Region, partition, and that the control-plane security group belongs to the derived VPC.

The `revision` participates in the access-reconciliation trigger. Publishing a new revision causes registered databases to reconcile on their next apply without exposing implementation details to application teams.

## Security group model

Each deployment receives one cluster-specific security group. It permits the selected database port only from:

- `allowed_security_group_ids`
- The discovered database-access control-plane security group

All source security groups must belong to the derived VPC. The facade does not accept CIDR rules, public ingress, caller-defined egress rules, or `0.0.0.0/0`. Aurora is never publicly accessible.

## Encryption ownership

The application-specific customer-managed KMS key is created and governed outside this module. It is a required input and has an explicit Terraform dependency from the application composition.

The facade uses that key for:

- Aurora cluster storage
- Automated backups and snapshots
- The RDS-managed master secret
- Database Insights / Performance Insights data
- CloudWatch database log groups

The facade validates that the key is:

- Enabled
- Symmetric
- Customer-managed
- Located in the current account and Region

Key-policy usability is ultimately enforced by AWS at apply time. The external key policy must permit the Terraform deployment principal and required AWS services to create grants and use the key.

Keeping the key outside the Aurora module means a cluster can be destroyed while retained snapshots remain decryptable. Key rotation, retention, policy administration, and eventual retirement belong to the application key owner.

The key owner must protect the key from deletion while any cluster, backup, or snapshot depends on it. The facade cannot enforce `prevent_destroy` on an externally managed key, so this is a required policy of the application-key module and its owning Terraform state.

## Database authorization model

### One login per IAM role

Every supplied IAM role maps to a distinct deterministic database login. The login name combines the permission tier with a stable truncated hash of the complete IAM role ARN.

The implementation validates generated-login uniqueness and keeps the reconciler username stable for the logical application boundary so a restored database can reuse its existing IAM-authenticated reconciler on a new physical cluster.

```text
arn:...:role/orders-api       -> runtime_<stable-hash>
arn:...:role/orders-worker    -> runtime_<stable-hash>
arn:...:role/orders-migrate   -> migrator_<stable-hash>
```

The complete mapping is an output. This enables independent revocation and workload-level auditability without asking developers to invent database usernames.

For each mapping, the facade attaches a narrowly scoped inline policy to the existing IAM role:

```text
Action:   rds-db:connect
Resource: arn:<partition>:rds-db:<region>:<account>:dbuser:<cluster-resource-id>/<database-user>
```

The facade never creates the supplied application IAM roles.

### Fixed permission tiers

Version 1 exposes fixed tiers only:

| Tier | Intended capability |
|---|---|
| Owner | Non-login database role that owns the application database objects. |
| Migrator | IAM login that can assume the owner role and perform DDL/DML inside the application boundary, without user administration or access to unrelated databases. |
| Runtime | IAM login with `SELECT`, `INSERT`, `UPDATE`, `DELETE`, sequence usage, and routine execution inside the application boundary. |
| Readonly | Optional IAM login with `SELECT` and routine execution. |
| Monitor | Optional IAM login with the engine-specific read-only statistics and query-observability permissions required by monitoring agents. |
| Reconciler | Privileged IAM login used only by the shared access control plane to maintain this contract. |

For PostgreSQL:

- The module creates the explicitly requested database and dedicated schema.
- IAM login roles receive `rds_iam`; this module manages no database password for them.
- `PUBLIC` privileges are revoked from the application database and schema.
- The owner is a non-login role.
- Migrations use `SET ROLE` to the owner so object ownership remains stable.
- Default privileges ensure future objects inherit runtime and read-only grants.

For MySQL:

- The module creates only the explicitly requested database.
- IAM login users use `AWSAuthenticationPlugin` and receive no conventional database password.
- MySQL roles implement the fixed tiers.
- Grants are scoped to `<database_name>.*`.
- There is no separate `schema_name` because MySQL schemas and databases are the same object.

There is no arbitrary-grant escape hatch in version 1.

## Bootstrap and reconciliation

### Per-deployment target role

Each Aurora deployment creates one lightweight IAM target role with:

- Trust limited to the discovered `target_role_principal_arn`.
- Permanent `rds-db:connect` permission only for that cluster's deterministic reconciler username.
- No permanent Secrets Manager permission.

The target role cannot modify its own policies. The shared cleanup workflow is the only principal allowed to add and remove its temporary bootstrap policy.

### Direct Terraform lifecycle invocation

Terraform uses the native `aws_lambda_invocation` resource with `lifecycle_scope = "CRUD"`. There is no CloudFormation bridge.

Conceptually:

```hcl
resource "aws_lambda_invocation" "database_access" {
  function_name   = local.control_plane.dispatcher_function_name
  qualifier       = local.control_plane.dispatcher_qualifier
  lifecycle_scope = "CRUD"

  input = jsonencode(local.database_access_contract)

  triggers = {
    desired_state_hash     = sha256(jsonencode(local.database_access_contract))
    control_plane_revision = local.control_plane.revision
  }

  depends_on = [
    module.aurora,
    aws_iam_role_policy.database_connect
  ]
}
```

The payload contains identifiers and desired state, never credentials:

- Cluster identifier, resource ID, endpoint, instance endpoints, and port
- Engine and pinned engine version
- Database name and optional PostgreSQL schema name
- Master-secret ARN and application KMS key ARN
- Target-role ARN
- IAM-role-to-database-user mappings and fixed permission tiers
- Desired-state hash

Create, update, and delete actions are synchronous from Terraform's perspective. The dispatcher starts a Standard Step Functions execution, polls it under a strict timeout below Lambda's 15-minute maximum, and returns success only after the workflow completes. Failures propagate as Lambda invocation errors and fail `terraform apply`.

The workflow and dispatcher are idempotent. A dispatcher timeout can fail Terraform while a Standard workflow continues, so a later apply must safely observe or resume the same desired-state operation rather than create a conflicting bootstrap.

### Bootstrap lifecycle

For a new or restored cluster, the shared control plane:

1. Attempts to connect using the IAM-authenticated reconciler identity.
2. If that succeeds, skips master-secret bootstrap and performs ongoing reconciliation.
3. If the reconciler is absent and bootstrap is not complete, the cleanup workflow attaches a temporary inline policy to the target role.
4. The temporary policy permits `secretsmanager:GetSecretValue` for only the cluster's RDS-managed master secret and permits KMS use only for the application key through Secrets Manager. It contains an absolute `aws:CurrentTime` expiry.
5. The bootstrap Lambda assumes the target role, retrieves the master credential, and creates the IAM-authenticated reconciler identity.
6. The workflow verifies a fresh IAM-authenticated connection as the reconciler.
7. The workflow calls `ModifyDBCluster` with `RotateMasterUserPassword=true` and `ApplyImmediately=true`.
8. The unconditional cleanup path removes temporary secret access and updates the target role's `AWSRevokeOlderSessions` deny so sessions issued before cleanup can no longer call AWS APIs.
9. The workflow records bootstrap completion and audit evidence in the shared control-plane datastore.

If master-password rotation fails after the reconciler was created, the workflow records bootstrap as incomplete. A later idempotent execution can connect using IAM, retry rotation without reading the secret, and complete cleanup bookkeeping.

The RDS-managed master secret remains available only for externally governed break-glass use. Ongoing access reconciliation never reads it.

### Ongoing reconciliation

Create and update operations converge the database to the desired fixed permission contract. Additions are created and verified before apply succeeds. Removed IAM roles lose their exact `rds-db:connect` policy and corresponding database login; the reconciler handles the database-side revocation idempotently.

Delete unregisters the deployment while the cluster and target role still exist. Terraform dependency reversal ensures the Lambda delete invocation runs before its Aurora and IAM dependencies are destroyed.

An SQS queue and DLQ may receive immutable success and failure audit messages, but queues are audit transport only. They are not the correctness mechanism; Step Functions cleanup and the synchronous Terraform result determine success.

## Recovery

Normal creation uses `recovery = null`.

### Snapshot restore

```hcl
recovery = {
  mode                = "snapshot"
  snapshot_identifier = "arn:aws:rds:us-east-1:123456789012:cluster-snapshot:orders-final"
}
```

### Point-in-time restore

Latest restorable time:

```hcl
recovery = {
  mode                      = "point-in-time"
  source_cluster_identifier = "commercial-prod-orders"
}
```

Specific time:

```hcl
recovery = {
  mode                      = "point-in-time"
  source_cluster_identifier = "commercial-prod-orders"
  restore_time              = "2026-08-13T14:35:00Z"
  target_suffix             = "recovery-20260813"
}
```

Rules:

- Snapshot mode requires `snapshot_identifier` and rejects point-in-time fields.
- Point-in-time mode requires `source_cluster_identifier`.
- Omitting `restore_time` selects the latest restorable time.
- A supplied time must be RFC 3339 and inside the source recovery window.
- Aurora always creates a new physical cluster; recovery never overwrites an existing cluster.
- Source metadata is discovered and validated rather than re-entered.
- The source cluster or snapshot must be encrypted with the same application KMS key supplied to the recovery deployment. Restore does not re-encrypt under a different key; snapshot copying and re-encryption remain external workflows.
- The target receives the selected stage, compute, networking, observability, access, and protection profiles.
- The target therefore remains encrypted with the supplied application KMS key.
- The explicit `database_name` and PostgreSQL `schema_name` form the desired contract and are verified after restore.
- The access reconciler first tries any restored IAM reconciler identity, then bootstraps only if necessary.

Snapshot copying, sharing, cross-account orchestration, cross-Region orchestration, application cutover, and source-cluster retirement remain outside this module.

## Observability boundary

The module produces AWS-native, vendor-neutral telemetry. Organization-level observability tooling owns collection, forwarding, long-term storage, dashboards, alerts, paging, and SLOs.

The facade:

- Leaves standard Aurora CloudWatch metrics enabled.
- Enables stage-derived Enhanced Monitoring.
- Enables Database Insights Standard and the corresponding encrypted performance telemetry.
- Publishes supported engine, slow-query, and IAM-authentication-error logs to CloudWatch Logs.
- Applies consistent canonical tags for account-level discovery.
- Exposes log-group ARNs, cluster and instance resource IDs, and instance endpoints.
- Supports optional fixed monitor identities for agents that need direct database access.

CloudWatch log retention is a durable AWS buffer, not the organization's only retention system. Forwarding infrastructure is shared and therefore not created per database.

Deep query telemetry does not necessarily flow through ordinary CloudWatch metrics. Datadog DBM, Grafana Database Observability, and similar agents may connect directly to individual Aurora instance endpoints using the optional monitor IAM identities and their own network placement.

## Backup boundary

The module owns:

- Aurora-native automated backups
- Stage-derived backup retention
- Copying tags to snapshots
- The required final snapshot for staging and production deletion

Central AWS Backup infrastructure owns:

- Backup plans and tag selection
- Vaults and vault lock
- Cross-account and cross-Region copies
- Regulatory retention
- Legal holds
- Central restore governance

Canonical tags make the cluster selectable by organization-level backup policies.

## Change management

- RDS API engine versions are exact, tested profile values.
- Opt-in automatic minor-version advancement is disabled.
- Facade releases promote tested selectable engine versions. AWS-managed or mandatory Aurora patches within a selected line remain AWS's responsibility and cannot be pinned independently by Terraform.
- Dev and test apply ordinary changes immediately.
- Staging and production defer rebooting or disruptive changes to maintenance windows.
- Backup and maintenance windows are deterministic hashes of the application identity and do not overlap.
- `apply_immediately = true` is an explicit operational override for urgent changes.
- Major-version upgrades require a facade release/profile and an explicit engine-version change; they are never silently automated.

## Decommissioning

Dev and test are intentionally disposable. They have no deletion protection and skip the final snapshot.

Staging and production use a simple two-apply process:

1. While the module is still present, set `decommission = true` and apply. This disables Aurora deletion protection but does not delete the cluster.
2. Review the subsequent plan that removes the module, then apply it. Terraform unregisters database access and deletes Aurora with a deterministic, unique final-snapshot identifier.

`decommission = true` is valid only for staging and production. The preparation apply should be followed promptly by the reviewed removal apply so a protected cluster is not left unprotected indefinitely.

If a protected module is removed without the preparation apply, AWS rejects cluster deletion because deletion protection is still enabled. Terraform cannot express that guard as a plan-time assertion after the module configuration itself has been removed, so documentation and tests must describe it as an apply-time AWS protection.

The externally managed application KMS key remains untouched and keeps retained snapshots decryptable. Central backup and key governance determine when recovery artifacts and the key may eventually be retired.

## Resource ownership and dependency order

The facade owns or configures:

- The official Aurora module invocation and resulting cluster and instances
- Cluster-specific security group
- Cluster and instance parameter groups
- CloudWatch database log groups
- Enhanced Monitoring IAM role
- RDS-managed master-secret configuration
- Cluster-specific bootstrap/reconciler target role
- Exact `rds-db:connect` inline policies on supplied workload roles
- Direct `aws_lambda_invocation` lifecycle record
- Stable randomness used for unique final-snapshot naming

The facade references but never manages:

- VPC, subnets, routes, NAT gateways, and DB subnet group
- Application KMS key
- Application IAM roles and security groups
- Shared database-access control plane
- Central observability and AWS Backup infrastructure

Creation order:

```text
Discover and validate external contracts
        -> Create security, logging, monitoring, and parameter resources
        -> Create Aurora through the official module
        -> Attach exact workload rds-db:connect policies
        -> Invoke the shared access control plane synchronously
        -> Expose the ready connection contract
```

Terraform destroys in reverse dependency order, so delete reconciliation occurs while the cluster, target role, and database connection path still exist.

## Outputs

### Connection output

PostgreSQL:

```hcl
connection = {
  writer_endpoint = "..."
  reader_endpoint = "..."
  port            = 5432
  database_name   = "ordersdb"
  schema_name     = "orders"
  ssl_mode        = "verify-full"
}
```

MySQL uses `schema_name = null` in the stable output shape:

```hcl
connection = {
  writer_endpoint = "..."
  reader_endpoint = "..."
  port            = 3306
  database_name   = "ordersdb"
  schema_name     = null
  ssl_mode        = "VERIFY_IDENTITY"
}
```

The reader endpoint is always exposed, but a single-instance dev or test cluster does not provide separate reader capacity.

### Database-user mapping

```hcl
database_users = {
  runtime = {
    "arn:aws:iam::123456789012:role/orders-api" = "runtime_7a2c41d9"
  }
  migrator = {
    "arn:aws:iam::123456789012:role/orders-migrations" = "migrator_f42a9130"
  }
  readonly = {}
  monitor  = {}
}
```

### Operational outputs

- Cluster identifier, ARN, and resource ID
- Instance identifiers and endpoints
- Security-group ID
- DB subnet-group name and derived VPC ID
- CloudWatch log-group ARNs
- RDS-managed master-secret ARN for authorized break-glass tooling
- Application KMS key ARN
- Desired access-contract hash and reconciliation result

No password, IAM token, secret value, or credential-bearing connection string is exposed. Terraform completes only after access reconciliation succeeds, so the reconciliation result is evidence rather than a bypassable readiness toggle.

## Validation and failure handling

Plan-time validation covers everything Terraform can know safely:

- Allowed stage, engine, compute, size, storage, and insights values
- Environment identifier format
- Engine-specific database and schema requirements
- Application KMS key metadata
- Network and control-plane SSM schema versions and live metadata
- DB subnet-group status, tags, VPC, and AZ count
- Source security-group VPC membership
- IAM-role account membership and conflicting-tier overlap
- Generated database-login uniqueness
- Engine/version/compute/instance-class orderability in the target Region
- Recovery field consistency and recoverable-time metadata where available

Apply fails if:

- AWS cannot use the application KMS key policy.
- Aurora cannot become available.
- The control-plane Lambda cannot be invoked.
- Bootstrap, temporary-policy cleanup, session revocation, or master-password rotation fails.
- IAM authentication verification fails.
- Database permission reconciliation fails.

Failure messages identify the failed external contract or lifecycle stage without including credentials or secret values.

## Testing strategy

Every change runs:

- `terraform fmt -check`
- `terraform validate`
- TFLint
- Generated documentation consistency checks
- Native `terraform test` unit tests with mocked AWS data

Mocked tests cover the full engine, stage, compute-mode, and size policy matrix, plus negative tests for:

- PostgreSQL without `schema_name`
- MySQL with `schema_name`
- Invalid or reserved logical identifiers
- Malformed or unsupported SSM contracts
- Subnet-group tag, VPC, status, or AZ mismatches
- Cross-account or wrong-VPC IAM/security inputs
- IAM-role overlap across tiers
- Invalid KMS key metadata
- Unsupported engine/version/class/Region combinations
- Invalid recovery combinations
- Recovery-source encryption or KMS-key mismatch
- Decommission policy derivation
- Canonical-tag protection

Policy and payload tests verify:

- Exact `rds-db:connect` resource scoping
- Target-role trust and permanent permissions
- Temporary bootstrap policy scope and absolute expiry
- KMS-via-Secrets-Manager conditions
- Create, update, delete, recovery, role-addition, and role-removal Lambda payloads
- Desired-state and control-plane revision triggers
- No credential values in outputs or invocation payloads

Cost-bearing AWS integration tests run in dedicated test accounts for releases or on a schedule:

- PostgreSQL serverless dev
- PostgreSQL provisioned production topology
- MySQL serverless dev
- MySQL provisioned production topology
- Snapshot restore
- Point-in-time restore
- Idempotent second apply
- IAM-role addition and independent revocation
- Disposable dev deletion
- Protected production preparation and final-snapshot deletion
- Control-plane failure propagation and bootstrap cleanup

The integration environment uses a real test database-access control plane and external KMS/network fixtures rather than weakening the module contract.

## Intended repository shape

This remains one public module. File boundaries organize implementation concerns without creating public submodules.

```text
.
├── README.md
├── versions.tf
├── variables.tf
├── locals.tf
├── data.tf
├── network.tf
├── security.tf
├── parameters.tf
├── monitoring.tf
├── aurora.tf
├── iam.tf
├── access-control.tf
├── outputs.tf
├── examples/
│   ├── postgres-serverless/
│   └── mysql-provisioned/
├── tests/
│   ├── policy-matrix.tftest.hcl
│   ├── validation.tftest.hcl
│   ├── iam.tftest.hcl
│   └── recovery.tftest.hcl
└── docs/
    └── superpowers/specs/
```

## References

- [Official Terraform Aurora module](https://github.com/terraform-aws-modules/terraform-aws-rds-aurora)
- [Official Aurora module v10.3.1 release](https://github.com/terraform-aws-modules/terraform-aws-rds-aurora/releases/tag/v10.3.1)
- [AWS provider `aws_lambda_invocation`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_invocation.html)
- [Aurora storage and encryption](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Overview.Encryption.html)
- [Aurora IAM database authentication](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/UsingWithRDS.IAMDBAuth.html)
- [Aurora-managed master password rotation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-secrets-manager.html)
- [Aurora serverless capacity](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.how-it-works.html)
- [CloudWatch Database Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Database-Insights.html)
- [Aurora snapshot restore](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-restore-snapshot.html)
- [Aurora point-in-time restore](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-pitr.html)
- [PostgreSQL schemas](https://www.postgresql.org/docs/current/ddl-schemas.html)
- [MySQL `CREATE DATABASE` / `CREATE SCHEMA`](https://dev.mysql.com/doc/refman/8.4/en/create-database.html)
