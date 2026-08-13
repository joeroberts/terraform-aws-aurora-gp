# Opinionated Aurora Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one developer-friendly Terraform facade that deploys an application-scoped Aurora PostgreSQL or Aurora MySQL cluster, derives secure stage policy, and synchronously registers database access with a separately owned shared control plane.

**Architecture:** The root module validates a small intent-based contract, discovers network and access-control metadata from versioned SSM parameters, and wraps `terraform-aws-modules/rds-aurora/aws` at an exact version. AWS-native resources attach least-privilege `rds-db:connect` policies to supplied roles and invoke the shared dispatcher through `aws_lambda_invocation`; the dispatcher and its Step Functions workflows remain external to this repository.

**Tech Stack:** Terraform 1.11.1+, HashiCorp AWS provider 6.54+, HashiCorp Random provider 3.6+, official Aurora module 10.3.1, native `terraform test`, TFLint AWS ruleset 0.47.0, terraform-docs 0.24.0, GitHub Actions.

## Global Constraints

- Terraform requirement is `>= 1.11.1, < 2.0`.
- AWS provider requirement is `>= 6.54, < 7.0`.
- Random provider requirement is `>= 3.6, < 4.0`.
- Pin `terraform-aws-modules/rds-aurora/aws` exactly to `10.3.1`; never expose a generic upstream-input map.
- The public engines are `postgresql` and `mysql`; the default is `postgresql`.
- The public compute modes are `serverless` and `provisioned`; the default is `serverless`.
- The public sizes are `small`, `medium`, `large`, and `xlarge`; the default is `small`.
- `stage` is exactly one of `dev`, `test`, `staging`, or `prod`; `environment` is a separate lowercase operating-boundary slug.
- PostgreSQL requires both `database_name` and `schema_name`; MySQL requires `database_name` and rejects `schema_name`.
- Do not create VPCs, subnets, NAT gateways, route tables, DB subnet groups, application roles, application security groups, application KMS keys, the shared access control plane, central backup resources, or vendor-specific observability resources.
- Require a same-account, same-Region, enabled, symmetric, customer-managed application KMS key.
- Never accept CIDR ingress or make Aurora publicly accessible.
- Use the versioned network contract `/platform/network/v1/<environment>/<stage>/<region>/aurora` and derive VPC ID from the live DB subnet group.
- Use the versioned control-plane contract `/platform/database-access/v1/<environment>/<region>/<vpc-id>/control-plane`.
- Application database access uses IAM authentication only; no password, token, secret value, or credential-bearing connection string may appear in state-backed outputs or Lambda payloads.
- The facade may expose the RDS-managed master-secret ARN, but never its value.
- Dev/test use one Aurora instance and are disposable; staging/prod use two instances in distinct AZs, deletion protection, and a final snapshot.
- Staging/prod deletion is a two-apply workflow: first apply `decommission = true`, then remove the module.
- Recovery always creates a new physical cluster and only accepts same-account, same-Region sources encrypted by the supplied application KMS key.
- Direct Terraform integration uses `aws_lambda_invocation` with `lifecycle_scope = "CRUD"`; CloudFormation, provisioners, CLI calls, and database providers are prohibited.
- A successful apply means the shared control plane returned success after database permission reconciliation and IAM-authentication verification.
- Canonical tags cannot be overridden by callers.
- Preserve one public module; file boundaries separate responsibilities, not public submodules.
- This plan implements the application Aurora facade only. The shared database-access control plane is a separately deployable subsystem with its own implementation plan; this repository defines its contract and exercises it as a black-box integration dependency.

---

## File Structure

| File | Responsibility |
|---|---|
| `versions.tf` | Terraform and provider compatibility declarations. |
| `variables.tf` | Small public input contract and single-variable validations. |
| `checks.tf` | Blocking `terraform_data` lifecycle preconditions for cross-variable and external metadata assertions. |
| `locals.tf` | Canonical names, tags, stage profiles, compute profiles, identities, and deterministic windows. |
| `data.tf` | AWS context, KMS, IAM role, security-group, and orderability lookups. |
| `network.tf` | Network and control-plane SSM discovery plus live subnet/VPC validation. |
| `parameters.tf` | Engine parameter and log-export profiles. |
| `recovery.tf` | Snapshot and point-in-time source discovery and restore arguments. |
| `aurora.tf` | Stable final-snapshot suffix and the exact official Aurora-module invocation. |
| `iam.tf` | Target role, reconciler permission, and supplied-workload connection policies. |
| `access-control.tf` | Versioned desired-state payload and CRUD Lambda invocation. |
| `outputs.tf` | Stable connection, identity, infrastructure, and reconciliation outputs. |
| `tests/validation.tftest.hcl` | Public-contract and negative validation tests. |
| `tests/policy-matrix.tftest.hcl` | Engine, stage, compute, size, parameter, and observability policy tests. |
| `tests/discovery.tftest.hcl` | SSM, network, KMS, IAM, security-group, and orderability contract tests. |
| `tests/recovery.tftest.hcl` | Snapshot and point-in-time validation tests. |
| `tests/iam.tftest.hcl` | Trust and exact `rds-db:connect` policy tests. |
| `tests/access-control.tftest.hcl` | Payload, lifecycle trigger, result, and credential-leak tests. |
| `tests/outputs.tftest.hcl` | Stable output-shape and sensitivity tests. |
| `examples/postgres-serverless/` | Minimal PostgreSQL/serverless consumer composition. |
| `examples/mysql-provisioned/` | Minimal MySQL/provisioned consumer composition. |
| `docs/contracts/database-access-control-plane-v1.md` | SSM and dispatcher payload contract consumed by this module. |
| `docs/operations/recovery.md` | Supported snapshot and point-in-time workflows. |
| `docs/operations/decommission.md` | Disposable and protected deletion workflows. |
| `.tflint.hcl` | Terraform and AWS lint policy. |
| `.terraform-docs.yml` | Reproducible generated-input/output documentation settings. |
| `.github/workflows/ci.yml` | Formatting, validation, lint, unit-test, and documentation gates. |
| `.github/workflows/integration.yml` | Approval-gated release/scheduled tests in dedicated AWS accounts. |
| `tests/integration/main.tf` | Real-AWS test composition around this module and external fixtures. |
| `tests/integration/variables.tf` | Real-AWS fixture identifiers and scenario inputs. |
| `scripts/validate-examples.sh` | Offline initialization and validation of both consumer examples. |
| `scripts/run-integration.sh` | Deterministic create/reapply/decommission/destroy orchestration. |
| `scripts/run-failure-integration.sh` | Forced-dispatcher-failure assertion and cleanup orchestration. |
| `.gitignore` | Terraform working-directory, state, plan, and crash-artifact exclusions. |
| `README.md` | Product contract, examples, ownership boundaries, and generated reference. |

---

### Task 1: Establish the Public Contract and Validation Boundary

**Files:**
- Create: `versions.tf`
- Create: `variables.tf`
- Create: `checks.tf`
- Create: `.gitignore`
- Create: `tests/validation.tftest.hcl`

**Interfaces:**
- Consumes: AWS provider configuration supplied by the root caller; no provider block is created by this module.
- Produces: The complete public variables used by every later task, plus blocking preconditions on `terraform_data.input_validation`.

- [ ] **Step 1: Write failing public-contract tests**

Create `tests/validation.tftest.hcl` with mock providers, one known-good input set, and explicit engine-specific failures:

```hcl
mock_provider "aws" {}
mock_provider "random" {}

variables {
  name                       = "orders"
  environment                = "commercial"
  stage                      = "dev"
  database_name              = "ordersdb"
  schema_name                = "orders"
  kms_key_arn                = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
  runtime_role_arns          = ["arn:aws:iam::123456789012:role/orders-api"]
  migrator_role_arns         = ["arn:aws:iam::123456789012:role/orders-migrate"]
}

run "postgres_requires_schema" {
  command = plan

  variables {
    schema_name = null
  }

  expect_failures = [var.schema_name]
}

run "mysql_rejects_schema" {
  command = plan

  variables {
    engine      = "mysql"
    schema_name = "orders"
  }

  expect_failures = [var.schema_name]
}

run "mysql_accepts_database_only" {
  command = plan

  variables {
    engine      = "mysql"
    schema_name = null
  }
}

run "rejects_role_in_two_tiers" {
  command = plan

  variables {
    readonly_role_arns = ["arn:aws:iam::123456789012:role/orders-api"]
  }

  expect_failures = [terraform_data.input_validation]
}

run "rejects_invalid_recovery_shape" {
  command = plan

  variables {
    recovery = {
      mode                      = "snapshot"
      snapshot_identifier       = "orders-final"
      source_cluster_identifier = "orders-source"
    }
  }

  expect_failures = [var.recovery]
}
```

Append these negative runs:

```hcl
run "rejects_invalid_stage" {
  command = plan
  variables { stage = "production" }
  expect_failures = [var.stage]
}

run "rejects_invalid_environment_slug" {
  command = plan
  variables { environment = "FedRAMP" }
  expect_failures = [var.environment]
}

run "rejects_invalid_name_slug" {
  command = plan
  variables { name = "orders--api" }
  expect_failures = [var.name]
}

run "rejects_reserved_database" {
  command = plan
  variables { database_name = "postgres" }
  expect_failures = [var.database_name]
}

run "requires_source_security_group" {
  command = plan
  variables { allowed_security_group_ids = [] }
  expect_failures = [var.allowed_security_group_ids]
}

run "requires_runtime_role" {
  command = plan
  variables { runtime_role_arns = [] }
  expect_failures = [var.runtime_role_arns]
}

run "requires_migrator_role" {
  command = plan
  variables { migrator_role_arns = [] }
  expect_failures = [var.migrator_role_arns]
}

run "protects_canonical_tags" {
  command = plan
  variables { tags = { Stage = "other" } }
  expect_failures = [var.tags]
}

run "rejects_unsupported_engine_family" {
  command = plan
  variables { engine_version = "18.1" }
  expect_failures = [terraform_data.input_validation]
}

run "rejects_dev_decommission" {
  command = plan
  variables { decommission = true }
  expect_failures = [var.decommission]
}

run "rejects_malformed_recovery_time" {
  command = plan
  variables {
    recovery = {
      mode                      = "point-in-time"
      source_cluster_identifier = "orders-source"
      restore_time              = "not-a-time"
    }
  }
  expect_failures = [var.recovery]
}

run "rejects_monitor_role_overlap" {
  command = plan
  variables {
    monitor_role_arns = ["arn:aws:iam::123456789012:role/orders-api"]
  }
  expect_failures = [terraform_data.input_validation]
}
```

- [ ] **Step 2: Run the contract test to verify it fails**

Run:

```bash
terraform test -filter=tests/validation.tftest.hcl
```

Expected: FAIL with unsupported root arguments because `variables.tf` does not exist.

- [ ] **Step 3: Declare exact Terraform and provider constraints**

Create `versions.tf`:

```hcl
terraform {
  required_version = ">= 1.11.1, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.54, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6, < 4.0"
    }
  }
}
```

- [ ] **Step 4: Implement the small public input contract**

Create `variables.tf`. Use the following exact types and defaults; keep descriptions developer-facing:

```hcl
variable "name" {
  type        = string
  description = "Application identity used for AWS names and canonical tags."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.name)) && !strcontains(var.name, "--")
    error_message = "name must be a 3-40 character lowercase slug."
  }
}

variable "environment" {
  type        = string
  description = "Operating boundary such as commercial, gov, or fedramp; not a deployment stage."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.environment)) && !strcontains(var.environment, "--")
    error_message = "environment must be a 3-32 character lowercase slug."
  }
}

variable "stage" {
  type        = string
  description = "Deployment lifecycle stage."

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.stage)
    error_message = "stage must be dev, test, staging, or prod."
  }
}

variable "engine" {
  type        = string
  description = "Aurora compatibility engine."
  default     = "postgresql"

  validation {
    condition     = contains(["postgresql", "mysql"], var.engine)
    error_message = "engine must be postgresql or mysql."
  }
}

variable "database_name" {
  type        = string
  description = "Explicit logical database name."

  validation {
    condition = (
      can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name)) &&
      !contains(["postgres", "template0", "template1", "rdsadmin", "mysql", "information_schema", "performance_schema", "sys"], var.database_name)
    )
    error_message = "database_name must be a lowercase unquoted identifier and not a protected system database."
  }
}

variable "schema_name" {
  type        = string
  description = "Dedicated PostgreSQL schema; prohibited for MySQL."
  default     = null

  validation {
    condition = var.engine == "postgresql" ? (
      var.schema_name != null &&
      can(regex("^[a-z][a-z0-9_]{0,62}$", var.schema_name)) &&
      !contains(["public", "pg_catalog", "information_schema", "rdsadmin"], var.schema_name)
    ) : var.schema_name == null
    error_message = "PostgreSQL requires a dedicated lowercase schema_name; MySQL prohibits schema_name."
  }
}

variable "kms_key_arn" {
  type        = string
  description = "Existing application-specific customer-managed KMS key ARN."

  validation {
    condition     = can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/[0-9a-fA-F-]{36}$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN, not an alias."
  }
}

variable "allowed_security_group_ids" {
  type        = set(string)
  description = "Existing application security groups allowed to connect."

  validation {
    condition     = length(var.allowed_security_group_ids) > 0 && alltrue([for id in var.allowed_security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", id))])
    error_message = "At least one valid source security-group ID is required."
  }
}

variable "runtime_role_arns" {
  type        = set(string)
  description = "Existing same-account workload roles receiving runtime access."

  validation {
    condition     = length(var.runtime_role_arns) > 0
    error_message = "At least one runtime role is required."
  }
}

variable "migrator_role_arns" {
  type        = set(string)
  description = "Existing same-account workload roles receiving migration access."

  validation {
    condition     = length(var.migrator_role_arns) > 0
    error_message = "At least one migrator role is required."
  }
}

variable "readonly_role_arns" {
  type        = set(string)
  description = "Existing same-account roles receiving read-only access."
  default     = []
}

variable "monitor_role_arns" {
  type        = set(string)
  description = "Existing same-account roles used by direct database monitoring agents."
  default     = []
}

variable "compute_mode" {
  type        = string
  description = "Aurora serverless v2 or provisioned instances."
  default     = "serverless"

  validation {
    condition     = contains(["serverless", "provisioned"], var.compute_mode)
    error_message = "compute_mode must be serverless or provisioned."
  }
}

variable "size" {
  type        = string
  description = "Curated capacity profile."
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "large", "xlarge"], var.size)
    error_message = "size must be small, medium, large, or xlarge."
  }
}

variable "storage_mode" {
  type        = string
  description = "Aurora storage pricing model."
  default     = "standard"

  validation {
    condition     = contains(["standard", "io-optimized"], var.storage_mode)
    error_message = "storage_mode must be standard or io-optimized."
  }
}

variable "database_insights_mode" {
  type        = string
  description = "CloudWatch Database Insights mode."
  default     = "standard"

  validation {
    condition     = contains(["standard", "advanced"], var.database_insights_mode)
    error_message = "database_insights_mode must be standard or advanced."
  }
}

variable "engine_version" {
  type        = string
  description = "Optional profile-compatible RDS API engine version."
  default     = null
}

variable "apply_immediately" {
  type        = bool
  description = "Override the stage-derived change schedule for an urgent operation."
  default     = null
}

variable "provisioned_instance_class" {
  type        = string
  description = "Optional orderability-validated provisioned instance-class override."
  default     = null

  validation {
    condition     = var.provisioned_instance_class == null || can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.provisioned_instance_class))
    error_message = "provisioned_instance_class must be a valid db.* class."
  }
}

variable "recovery" {
  type = object({
    mode                      = string
    snapshot_identifier       = optional(string)
    source_cluster_identifier = optional(string)
    restore_time              = optional(string)
    target_suffix             = optional(string)
  })
  description = "Optional snapshot or point-in-time recovery into a new physical cluster."
  default     = null

  validation {
    condition = var.recovery == null ? true : (
      contains(["snapshot", "point-in-time"], var.recovery.mode) &&
      (var.recovery.mode == "snapshot" ? (
        var.recovery.snapshot_identifier != null &&
        var.recovery.source_cluster_identifier == null &&
        var.recovery.restore_time == null
      ) : (
        var.recovery.snapshot_identifier == null &&
        var.recovery.source_cluster_identifier != null &&
        (var.recovery.restore_time == null || can(timecmp(var.recovery.restore_time, "2000-01-01T00:00:00Z")))
      )) &&
      (var.recovery.target_suffix == null ? true : (
        can(regex("^[a-z0-9][a-z0-9-]{0,22}[a-z0-9]$", var.recovery.target_suffix)) &&
        !strcontains(var.recovery.target_suffix, "--")
      ))
    )
    error_message = "recovery must select exactly one supported mode with its required fields and an optional RFC 3339 restore_time."
  }
}

variable "decommission" {
  type        = bool
  description = "Disable staging/prod deletion protection during the required preparation apply."
  default     = false

  validation {
    condition     = !var.decommission || contains(["staging", "prod"], var.stage)
    error_message = "decommission is valid only for staging or prod."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional non-canonical tags."
  default     = {}

  validation {
    condition = length(setintersection(
      toset(keys(var.tags)),
      toset(["Name", "Application", "Environment", "Stage", "ManagedBy", "Purpose"])
    )) == 0
    error_message = "tags cannot override canonical module tags."
  }
}
```

Create `.gitignore`:

```gitignore
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfplan
.terraform.lock.hcl
crash.log
crash.*.log
failure-apply.log
```

- [ ] **Step 5: Add blocking cross-variable preconditions**

Create `checks.tf` with one built-in `terraform_data` resource. Lifecycle preconditions fail planning; do not use top-level `check` blocks for mandatory policy because failed checks can continue as warnings:

```hcl
resource "terraform_data" "input_validation" {
  input = {
    engine       = var.engine
    stage        = var.stage
    compute_mode = var.compute_mode
  }

  lifecycle {
    precondition {
      condition = length(distinct(concat(
        tolist(var.runtime_role_arns),
        tolist(var.migrator_role_arns),
        tolist(var.readonly_role_arns),
        tolist(var.monitor_role_arns)
      ))) == sum([
        length(var.runtime_role_arns),
        length(var.migrator_role_arns),
        length(var.readonly_role_arns),
        length(var.monitor_role_arns)
      ])
      error_message = "An IAM role may belong to only one database permission tier."
    }

    precondition {
      condition = var.engine_version == null || (
        var.engine == "postgresql"
        ? can(regex("^17\\.[0-9]+$", var.engine_version))
        : can(regex("^8\\.4\\.mysql_aurora\\.8\\.4\\.[0-9]+$", var.engine_version))
      )
      error_message = "engine_version must remain inside the tested PostgreSQL 17 or Aurora MySQL 8.4 profile."
    }

    precondition {
      condition     = var.provisioned_instance_class == null || var.compute_mode == "provisioned"
      error_message = "provisioned_instance_class is valid only when compute_mode is provisioned."
    }
  }
}
```

- [ ] **Step 6: Run the contract tests**

Run:

```bash
terraform fmt -check
terraform init -backend=false
terraform validate
terraform test -filter=tests/validation.tftest.hcl
```

Expected: PASS for the valid MySQL case and every negative run reports only its declared expected failure.

- [ ] **Step 7: Commit the public contract**

```bash
git add .gitignore versions.tf variables.tf checks.tf tests/validation.tftest.hcl
git commit -m "feat: define the opinionated Aurora contract"
```

---

### Task 2: Implement Stage, Compute, Engine, and Observability Profiles

**Files:**
- Create: `locals.tf`
- Create: `parameters.tf`
- Create: `tests/policy-matrix.tftest.hcl`

**Interfaces:**
- Consumes: Public variables from Task 1.
- Produces: `local.stage_profile`, `local.engine_profile`, `local.serverless_scaling`, `local.instance_class_candidates`, `local.storage_type`, `local.performance_insights_retention`, `local.cluster_parameters`, `local.instance_parameters`, `local.log_exports`, `local.canonical_tags`, and deterministic maintenance windows.

- [ ] **Step 1: Write failing policy-matrix tests**

Create `tests/policy-matrix.tftest.hcl` with one run per meaningful policy edge. Use `command = plan` and assert root locals directly:

```hcl
mock_provider "aws" {}
mock_provider "random" {}

variables {
  name                       = "orders"
  environment                = "commercial"
  stage                      = "dev"
  database_name              = "ordersdb"
  schema_name                = "orders"
  kms_key_arn                = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
  runtime_role_arns          = ["arn:aws:iam::123456789012:role/orders-api"]
  migrator_role_arns         = ["arn:aws:iam::123456789012:role/orders-migrate"]
}

run "dev_serverless_small" {
  command = plan

  assert {
    condition     = local.stage_profile.instance_count == 1
    error_message = "dev must use one instance."
  }
  assert {
    condition     = local.serverless_scaling == { min_capacity = 0, max_capacity = 8, seconds_until_auto_pause = 900 }
    error_message = "dev small must scale from zero to eight ACUs and pause after fifteen minutes."
  }
  assert {
    condition     = local.stage_profile.backup_retention == 1 && local.stage_profile.log_retention == 7
    error_message = "dev retention profile changed unexpectedly."
  }
}

run "prod_serverless_xlarge" {
  command = plan

  variables {
    stage = "prod"
    size  = "xlarge"
  }

  assert {
    condition     = local.stage_profile.instance_count == 2 && local.stage_profile.deletion_protection
    error_message = "prod must be protected and highly available."
  }
  assert {
    condition     = local.serverless_scaling.min_capacity == 16 && local.serverless_scaling.max_capacity == 64
    error_message = "prod xlarge ACU profile changed unexpectedly."
  }
}

run "staging_provisioned_medium" {
  command = plan

  variables {
    stage        = "staging"
    compute_mode = "provisioned"
    size         = "medium"
  }

  assert {
    condition     = local.instance_class_candidates == ["db.r7g.xlarge", "db.r6g.xlarge"]
    error_message = "staging medium candidate order changed unexpectedly."
  }
}

run "mysql_profile" {
  command = plan

  variables {
    engine      = "mysql"
    schema_name = null
  }

  assert {
    condition     = local.engine_profile.aws_engine == "aurora-mysql" && local.engine_profile.engine_version == "8.4.mysql_aurora.8.4.7"
    error_message = "MySQL profile must use Aurora MySQL 8.4.7."
  }
  assert {
    condition     = contains(local.log_exports, "slowquery") && contains(local.log_exports, "iam-db-auth-error")
    error_message = "MySQL must export slow-query and IAM-authentication error logs."
  }
}
```

Append runs that lock the remaining policy tables and overrides:

```hcl
run "all_profile_tables_are_exact" {
  command = plan

  assert {
    condition = local.stage_profiles == {
      dev     = { instance_count = 1, backup_retention = 1, deletion_protection = false, skip_final_snapshot = true, apply_immediately = true, monitoring_interval = 60, log_retention = 7, slow_query_ms = 1000 }
      test    = { instance_count = 1, backup_retention = 3, deletion_protection = false, skip_final_snapshot = true, apply_immediately = true, monitoring_interval = 60, log_retention = 14, slow_query_ms = 1000 }
      staging = { instance_count = 2, backup_retention = 14, deletion_protection = true, skip_final_snapshot = false, apply_immediately = false, monitoring_interval = 15, log_retention = 30, slow_query_ms = 500 }
      prod    = { instance_count = 2, backup_retention = 35, deletion_protection = true, skip_final_snapshot = false, apply_immediately = false, monitoring_interval = 15, log_retention = 90, slow_query_ms = 500 }
    }
    error_message = "The four stage profiles changed unexpectedly."
  }

  assert {
    condition = local.serverless_min == {
      dev     = { small = 0, medium = 0, large = 0, xlarge = 0 }
      test    = { small = 0, medium = 0, large = 0, xlarge = 0 }
      staging = { small = 1, medium = 2, large = 4, xlarge = 8 }
      prod    = { small = 2, medium = 4, large = 8, xlarge = 16 }
    } && local.serverless_max == { small = 8, medium = 16, large = 32, xlarge = 64 }
    error_message = "The complete serverless size/stage matrix changed unexpectedly."
  }

  assert {
    condition = local.provisioned_candidates == {
      dev = {
        small = ["db.t4g.medium", "db.t3.medium"], medium = ["db.r7g.large", "db.r6g.large"], large = ["db.r7g.xlarge", "db.r6g.xlarge"], xlarge = ["db.r7g.2xlarge", "db.r6g.2xlarge"]
      }
      test = {
        small = ["db.t4g.medium", "db.t3.medium"], medium = ["db.r7g.large", "db.r6g.large"], large = ["db.r7g.xlarge", "db.r6g.xlarge"], xlarge = ["db.r7g.2xlarge", "db.r6g.2xlarge"]
      }
      staging = {
        small = ["db.r7g.large", "db.r6g.large"], medium = ["db.r7g.xlarge", "db.r6g.xlarge"], large = ["db.r7g.2xlarge", "db.r6g.2xlarge"], xlarge = ["db.r7g.4xlarge", "db.r6g.4xlarge"]
      }
      prod = {
        small = ["db.r7g.large", "db.r6g.large"], medium = ["db.r7g.xlarge", "db.r6g.xlarge"], large = ["db.r7g.2xlarge", "db.r6g.2xlarge"], xlarge = ["db.r7g.4xlarge", "db.r6g.4xlarge"]
      }
    }
    error_message = "The complete provisioned size/stage matrix changed unexpectedly."
  }
}

run "io_optimized_storage" {
  command = plan
  variables { storage_mode = "io-optimized" }
  assert {
    condition     = local.storage_type == "aurora-iopt1"
    error_message = "I/O-Optimized must map to aurora-iopt1."
  }
}

run "advanced_insights_retention" {
  command = plan
  variables { database_insights_mode = "advanced" }
  assert {
    condition     = local.performance_insights_retention == 465
    error_message = "Advanced Database Insights must retain performance data for 465 days."
  }
}

run "urgent_apply_override" {
  command = plan
  variables { stage = "prod", apply_immediately = true }
  assert {
    condition     = local.apply_immediately
    error_message = "The explicit urgent-change override must win over the prod schedule."
  }
}

run "prod_decommission_preserves_snapshot" {
  command = plan
  variables { stage = "prod", decommission = true }
  assert {
    condition     = !local.stage_profile.deletion_protection && !local.stage_profile.skip_final_snapshot
    error_message = "Decommission must disable protection without disabling the final snapshot."
  }
}

run "windows_and_tags_are_deterministic" {
  command = plan
  assert {
    condition     = startswith(local.preferred_backup_window, "02:") && startswith(local.preferred_maintenance_window, "sun:04:")
    error_message = "Backup and maintenance windows must stay in separate deterministic hours."
  }
  assert {
    condition = (
      local.canonical_tags.Application == "orders" &&
      local.canonical_tags.Environment == "commercial" &&
      local.canonical_tags.Stage == "dev" &&
      local.canonical_tags.ManagedBy == "Terraform" &&
      local.canonical_tags.Purpose == "aurora"
    )
    error_message = "Canonical tags changed unexpectedly."
  }
}
```

- [ ] **Step 2: Run the matrix test to verify it fails**

Run:

```bash
terraform test -filter=tests/policy-matrix.tftest.hcl
```

Expected: FAIL with undeclared local-value errors.

- [ ] **Step 3: Implement deterministic names, tags, and stage profiles**

Create the first half of `locals.tf`:

```hcl
locals {
  recovery_suffix = var.recovery == null ? null : coalesce(
    try(var.recovery.target_suffix, null),
    "recovery-${substr(sha256(jsonencode({
      mode                      = var.recovery.mode
      snapshot_identifier       = try(var.recovery.snapshot_identifier, null)
      source_cluster_identifier = try(var.recovery.source_cluster_identifier, null)
      restore_time              = try(var.recovery.restore_time, null)
    })), 0, 6)}"
  )
  raw_cluster_name = join("-", compact([
    var.environment,
    var.stage,
    var.name,
    local.recovery_suffix
  ]))
  cluster_name = length(local.raw_cluster_name) <= 63 ? local.raw_cluster_name : "${substr(local.raw_cluster_name, 0, 54)}-${substr(sha256(local.raw_cluster_name), 0, 8)}"

  canonical_tags = merge(var.tags, {
    Name        = local.cluster_name
    Application = var.name
    Environment = var.environment
    Stage       = var.stage
    ManagedBy   = "Terraform"
    Purpose     = "aurora"
  })

  stage_profiles = {
    dev = {
      instance_count      = 1
      backup_retention    = 1
      deletion_protection = false
      skip_final_snapshot = true
      apply_immediately   = true
      monitoring_interval = 60
      log_retention       = 7
      slow_query_ms       = 1000
    }
    test = {
      instance_count      = 1
      backup_retention    = 3
      deletion_protection = false
      skip_final_snapshot = true
      apply_immediately   = true
      monitoring_interval = 60
      log_retention       = 14
      slow_query_ms       = 1000
    }
    staging = {
      instance_count      = 2
      backup_retention    = 14
      deletion_protection = !var.decommission
      skip_final_snapshot = false
      apply_immediately   = false
      monitoring_interval = 15
      log_retention       = 30
      slow_query_ms       = 500
    }
    prod = {
      instance_count      = 2
      backup_retention    = 35
      deletion_protection = !var.decommission
      skip_final_snapshot = false
      apply_immediately   = false
      monitoring_interval = 15
      log_retention       = 90
      slow_query_ms       = 500
    }
  }

  stage_profile    = local.stage_profiles[var.stage]
  apply_immediately = coalesce(var.apply_immediately, local.stage_profile.apply_immediately)

  schedule_seed     = parseint(substr(sha256("${var.environment}:${var.stage}:${var.name}"), 0, 4), 16)
  backup_minute      = (local.schedule_seed % 2) * 15
  maintenance_minute = (floor(local.schedule_seed / 2) % 2) * 15
  preferred_backup_window = format(
    "02:%02d-02:%02d",
    local.backup_minute,
    local.backup_minute + 30
  )
  preferred_maintenance_window = format(
    "sun:04:%02d-sun:05:%02d",
    local.maintenance_minute,
    local.maintenance_minute
  )
}
```

- [ ] **Step 4: Implement engine and compute profiles**

Append to `locals.tf`:

```hcl
locals {
  engine_profiles = {
    postgresql = {
      aws_engine             = "aurora-postgresql"
      engine_version         = "17.9"
      parameter_family       = "aurora-postgresql17"
      port                   = 5432
      master_username        = "clusteradmin"
      ssl_mode               = "verify-full"
    }
    mysql = {
      aws_engine             = "aurora-mysql"
      engine_version         = "8.4.mysql_aurora.8.4.7"
      parameter_family       = "aurora-mysql8.4"
      port                   = 3306
      master_username        = "clusteradmin"
      ssl_mode               = "VERIFY_IDENTITY"
    }
  }

  engine_profile = merge(local.engine_profiles[var.engine], {
    engine_version = coalesce(var.engine_version, local.engine_profiles[var.engine].engine_version)
  })

  serverless_max = {
    small = 8
    medium = 16
    large = 32
    xlarge = 64
  }
  serverless_min = {
    dev     = { small = 0, medium = 0, large = 0, xlarge = 0 }
    test    = { small = 0, medium = 0, large = 0, xlarge = 0 }
    staging = { small = 1, medium = 2, large = 4, xlarge = 8 }
    prod    = { small = 2, medium = 4, large = 8, xlarge = 16 }
  }
  serverless_scaling = var.compute_mode == "serverless" ? {
    min_capacity             = local.serverless_min[var.stage][var.size]
    max_capacity             = local.serverless_max[var.size]
    seconds_until_auto_pause = contains(["dev", "test"], var.stage) ? (var.stage == "dev" ? 900 : 1800) : null
  } : null

  provisioned_candidates = {
    dev = {
      small = ["db.t4g.medium", "db.t3.medium"]
      medium = ["db.r7g.large", "db.r6g.large"]
      large = ["db.r7g.xlarge", "db.r6g.xlarge"]
      xlarge = ["db.r7g.2xlarge", "db.r6g.2xlarge"]
    }
    test = {
      small = ["db.t4g.medium", "db.t3.medium"]
      medium = ["db.r7g.large", "db.r6g.large"]
      large = ["db.r7g.xlarge", "db.r6g.xlarge"]
      xlarge = ["db.r7g.2xlarge", "db.r6g.2xlarge"]
    }
    staging = {
      small = ["db.r7g.large", "db.r6g.large"]
      medium = ["db.r7g.xlarge", "db.r6g.xlarge"]
      large = ["db.r7g.2xlarge", "db.r6g.2xlarge"]
      xlarge = ["db.r7g.4xlarge", "db.r6g.4xlarge"]
    }
    prod = {
      small = ["db.r7g.large", "db.r6g.large"]
      medium = ["db.r7g.xlarge", "db.r6g.xlarge"]
      large = ["db.r7g.2xlarge", "db.r6g.2xlarge"]
      xlarge = ["db.r7g.4xlarge", "db.r6g.4xlarge"]
    }
  }
  instance_class_candidates = var.compute_mode == "serverless" ? ["db.serverless"] : (
    var.provisioned_instance_class != null
    ? [var.provisioned_instance_class]
    : local.provisioned_candidates[var.stage][var.size]
  )
  storage_type                    = var.storage_mode == "io-optimized" ? "aurora-iopt1" : "aurora"
  performance_insights_retention = var.database_insights_mode == "advanced" ? 465 : 7
}
```

- [ ] **Step 5: Implement exact engine parameter profiles**

Create `parameters.tf`:

```hcl
locals {
  postgres_cluster_parameters = [
    { name = "rds.force_ssl", value = "1", apply_method = "pending-reboot" },
    { name = "shared_preload_libraries", value = "pg_stat_statements,pgaudit", apply_method = "pending-reboot" },
    { name = "log_connections", value = "1", apply_method = "immediate" },
    { name = "log_disconnections", value = "1", apply_method = "immediate" },
    { name = "log_lock_waits", value = "1", apply_method = "immediate" },
    { name = "log_min_duration_statement", value = tostring(local.stage_profile.slow_query_ms), apply_method = "immediate" },
    { name = "pgaudit.log", value = var.stage == "dev" ? "none" : "ddl,role", apply_method = "immediate" }
  ]

  mysql_cluster_parameters = [
    { name = "require_secure_transport", value = "1", apply_method = "immediate" },
    { name = "slow_query_log", value = "1", apply_method = "immediate" },
    { name = "long_query_time", value = format("%.1f", local.stage_profile.slow_query_ms / 1000), apply_method = "immediate" },
    { name = "server_audit_logging", value = var.stage == "dev" ? "0" : "1", apply_method = "immediate" },
    { name = "server_audit_events", value = var.stage == "dev" ? "" : "CONNECT,QUERY_DDL,QUERY_DCL", apply_method = "immediate" }
    { name = "server_audit_logs_upload", value = var.stage == "dev" ? "0" : "1", apply_method = "immediate" }
  ]

  mysql_instance_parameters = [
    { name = "performance_schema", value = "1", apply_method = "pending-reboot" }
  ]

  cluster_parameters  = var.engine == "postgresql" ? local.postgres_cluster_parameters : local.mysql_cluster_parameters
  instance_parameters = var.engine == "postgresql" ? [] : local.mysql_instance_parameters
  log_exports = var.engine == "postgresql" ? [
    "postgresql",
    "iam-db-auth-error"
  ] : compact([
    var.stage == "dev" ? null : "audit",
    "error",
    "slowquery",
    "iam-db-auth-error"
  ])
}
```

- [ ] **Step 6: Run and expand the policy matrix**

Run:

```bash
terraform fmt
terraform validate
terraform test -filter=tests/policy-matrix.tftest.hcl
```

Expected: PASS for every stage/engine/compute/size assertion. Confirm the test count covers 4 stages × 4 sizes for serverless minimums and maximums, all 16 provisioned stage/size candidate lists, both parameter profiles, both storage modes, and both insights modes.

- [ ] **Step 7: Commit the policy profiles**

```bash
git add locals.tf parameters.tf tests/policy-matrix.tftest.hcl
git commit -m "feat: add curated Aurora policy profiles"
```

---

### Task 3: Discover and Validate External Platform Contracts

**Files:**
- Create: `data.tf`
- Create: `network.tf`
- Modify: `checks.tf`
- Create: `tests/discovery.tftest.hcl`
- Create: `docs/contracts/database-access-control-plane-v1.md`

**Interfaces:**
- Consumes: Network SSM v1, control-plane SSM v1, supplied KMS ARN, supplied workload-role ARNs, and supplied source security-group IDs.
- Produces: `local.network_contract`, `local.control_plane_contract`, `local.vpc_id`, `local.database_azs`, `local.workload_roles`, validated KMS metadata, the selected orderable instance class, blocking preconditions on `terraform_data.external_validation`, and contract documentation used by the separate control-plane project.

- [ ] **Step 1: Write failing discovery-contract tests**

Create `tests/discovery.tftest.hcl`. The happy-path run must override every external lookup with deterministic values:

```hcl
mock_provider "aws" {}
mock_provider "random" {}

variables {
  name                       = "orders"
  environment                = "commercial"
  stage                      = "prod"
  database_name              = "ordersdb"
  schema_name                = "orders"
  kms_key_arn                = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  allowed_security_group_ids = ["sg-0123456789abcdef0"]
  runtime_role_arns          = ["arn:aws:iam::123456789012:role/orders-api"]
  migrator_role_arns         = ["arn:aws:iam::123456789012:role/orders-migrate"]
}

override_data {
  target = data.aws_caller_identity.current
  values = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:user/terraform" }
}

override_data {
  target = data.aws_partition.current
  values = { partition = "aws", dns_suffix = "amazonaws.com" }
}

override_data {
  target = data.aws_region.current
  values = { name = "us-east-1" }
}

override_data {
  target = data.aws_ssm_parameter.network
  values = {
    value = jsonencode({ schema_version = 1, db_subnet_group_name = "commercial-prod-use1-aurora" })
  }
}

override_data {
  target = data.aws_db_subnet_group.database
  values = {
    arn        = "arn:aws:rds:us-east-1:123456789012:subgrp:commercial-prod-use1-aurora"
    name       = "commercial-prod-use1-aurora"
    status     = "Complete"
    subnet_ids = ["subnet-aaaaaaaa", "subnet-bbbbbbbb"]
    vpc_id     = "vpc-0123456789abcdef0"
  }
}

override_data {
  target = data.aws_subnet.database["subnet-aaaaaaaa"]
  values = { id = "subnet-aaaaaaaa", vpc_id = "vpc-0123456789abcdef0", availability_zone = "us-east-1a", state = "available" }
}

override_data {
  target = data.aws_subnet.database["subnet-bbbbbbbb"]
  values = { id = "subnet-bbbbbbbb", vpc_id = "vpc-0123456789abcdef0", availability_zone = "us-east-1b", state = "available" }
}

override_data {
  target = data.aws_resourcegroupstaggingapi_resources.database_subnet_group
  values = {
    resource_tag_mapping_list = [{
      resource_arn = "arn:aws:rds:us-east-1:123456789012:subgrp:commercial-prod-use1-aurora"
      tags = {
        Environment = "commercial"
        Stage       = "prod"
        Purpose     = "aurora"
      }
    }]
  }
}

override_data {
  target = data.aws_ssm_parameter.control_plane
  values = {
    value = jsonencode({
      schema_version               = 1
      dispatcher_function_name     = "database-access-dispatcher"
      dispatcher_qualifier         = "live"
      target_role_principal_arn    = "arn:aws:iam::123456789012:role/database-access-worker"
      revision                     = "2026-08-01.1"
      security_group_id            = "sg-0fedcba9876543210"
    })
  }
}

override_data {
  target = data.aws_security_group.control_plane
  values = { id = "sg-0fedcba9876543210", vpc_id = "vpc-0123456789abcdef0" }
}

override_data {
  target = data.aws_security_group.allowed["sg-0123456789abcdef0"]
  values = { id = "sg-0123456789abcdef0", vpc_id = "vpc-0123456789abcdef0" }
}

override_data {
  target = data.aws_kms_key.application
  values = {
    arn         = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    enabled     = true
    key_manager = "CUSTOMER"
    key_spec    = "SYMMETRIC_DEFAULT"
    key_usage   = "ENCRYPT_DECRYPT"
  }
}

override_data {
  target = data.aws_rds_orderable_db_instance.selected
  values = { instance_class = "db.serverless", engine = "aurora-postgresql", engine_version = "17.9", storage_type = "aurora" }
}

override_data {
  target = data.aws_lambda_function.dispatcher
  values = {
    function_name = "database-access-dispatcher"
    qualifier     = "live"
    arn           = "arn:aws:lambda:us-east-1:123456789012:function:database-access-dispatcher:live"
  }
}

override_data {
  target = data.aws_iam_role.workload["arn:aws:iam::123456789012:role/orders-api"]
  values = { name = "orders-api", arn = "arn:aws:iam::123456789012:role/orders-api" }
}

override_data {
  target = data.aws_iam_role.workload["arn:aws:iam::123456789012:role/orders-migrate"]
  values = { name = "orders-migrate", arn = "arn:aws:iam::123456789012:role/orders-migrate" }
}

run "valid_external_contracts" {
  command = plan

  assert {
    condition     = local.vpc_id == "vpc-0123456789abcdef0"
    error_message = "VPC ID must be derived from the DB subnet group."
  }
  assert {
    condition     = local.database_azs == ["us-east-1a", "us-east-1b"]
    error_message = "Database AZs must come from live subnet metadata."
  }
}
```

Append these focused negative runs; run-local overrides replace the matching happy-path override:

```hcl
run "rejects_malformed_network_contract" {
  command = plan
  override_data {
    target = data.aws_ssm_parameter.network
    values = { value = "{" }
  }
  expect_failures = [terraform_data.network_contract_shape]
}

run "rejects_unsupported_network_contract_version" {
  command = plan
  override_data {
    target = data.aws_ssm_parameter.network
    values = { value = jsonencode({ schema_version = 2, db_subnet_group_name = "commercial-prod-use1-aurora" }) }
  }
  expect_failures = [terraform_data.network_contract_shape]
}

run "rejects_malformed_control_plane_contract" {
  command = plan
  override_data {
    target = data.aws_ssm_parameter.control_plane
    values = { value = "not-json" }
  }
  expect_failures = [terraform_data.control_plane_contract_shape]
}

run "rejects_incomplete_subnet_group" {
  command = plan
  override_data {
    target = data.aws_db_subnet_group.database
    values = { arn = "arn:aws:rds:us-east-1:123456789012:subgrp:commercial-prod-use1-aurora", name = "commercial-prod-use1-aurora", status = "Incomplete", subnet_ids = ["subnet-aaaaaaaa", "subnet-bbbbbbbb"], vpc_id = "vpc-0123456789abcdef0" }
  }
  expect_failures = [terraform_data.external_validation]
}

run "rejects_one_az_subnet_group" {
  command = plan
  override_data {
    target = data.aws_subnet.database["subnet-bbbbbbbb"]
    values = { id = "subnet-bbbbbbbb", vpc_id = "vpc-0123456789abcdef0", availability_zone = "us-east-1a", state = "available" }
  }
  expect_failures = [terraform_data.external_validation]
}

run "rejects_subnet_vpc_mismatch" {
  command = plan
  override_data {
    target = data.aws_subnet.database["subnet-bbbbbbbb"]
    values = { id = "subnet-bbbbbbbb", vpc_id = "vpc-99999999999999999", availability_zone = "us-east-1b", state = "available" }
  }
  expect_failures = [terraform_data.external_validation]
}

run "rejects_missing_subnet_group_tags" {
  command = plan
  override_data {
    target = data.aws_resourcegroupstaggingapi_resources.database_subnet_group
    values = { resource_tag_mapping_list = [] }
  }
  expect_failures = [terraform_data.external_validation]
}

run "rejects_wrong_vpc_source_group" {
  command = plan
  override_data {
    target = data.aws_security_group.allowed["sg-0123456789abcdef0"]
    values = { id = "sg-0123456789abcdef0", vpc_id = "vpc-99999999999999999" }
  }
  expect_failures = [terraform_data.external_validation]
}

run "rejects_wrong_vpc_control_plane_group" {
  command = plan
  override_data {
    target = data.aws_security_group.control_plane
    values = { id = "sg-0fedcba9876543210", vpc_id = "vpc-99999999999999999" }
  }
  expect_failures = [terraform_data.external_validation]
}

run "rejects_cross_account_worker" {
  command = plan
  override_data {
    target = data.aws_ssm_parameter.control_plane
    values = {
      value = jsonencode({ schema_version = 1, dispatcher_function_name = "database-access-dispatcher", dispatcher_qualifier = "live", target_role_principal_arn = "arn:aws:iam::999999999999:role/database-access-worker", revision = "2026-08-01.1", security_group_id = "sg-0fedcba9876543210" })
    }
  }
  expect_failures = [terraform_data.external_validation]
}

run "rejects_cross_account_dispatcher" {
  command = plan
  override_data {
    target = data.aws_lambda_function.dispatcher
    values = { function_name = "database-access-dispatcher", qualifier = "live", arn = "arn:aws:lambda:us-east-1:999999999999:function:database-access-dispatcher:live" }
  }
  expect_failures = [terraform_data.external_validation]
}

run "rejects_disabled_kms_key" {
  command = plan
  override_data {
    target = data.aws_kms_key.application
    values = { arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555", enabled = false, key_manager = "CUSTOMER", key_spec = "SYMMETRIC_DEFAULT", key_usage = "ENCRYPT_DECRYPT" }
  }
  expect_failures = [terraform_data.external_validation]
}

run "rejects_aws_managed_kms_key" {
  command = plan
  override_data {
    target = data.aws_kms_key.application
    values = { arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555", enabled = true, key_manager = "AWS", key_spec = "SYMMETRIC_DEFAULT", key_usage = "ENCRYPT_DECRYPT" }
  }
  expect_failures = [terraform_data.external_validation]
}

run "rejects_asymmetric_kms_key" {
  command = plan
  override_data {
    target = data.aws_kms_key.application
    values = { arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555", enabled = true, key_manager = "CUSTOMER", key_spec = "RSA_2048", key_usage = "ENCRYPT_DECRYPT" }
  }
  expect_failures = [terraform_data.external_validation]
}

run "rejects_cross_account_kms_key" {
  command = plan
  override_data {
    target = data.aws_kms_key.application
    values = { arn = "arn:aws:kms:us-east-1:999999999999:key/11111111-2222-3333-4444-555555555555", enabled = true, key_manager = "CUSTOMER", key_spec = "SYMMETRIC_DEFAULT", key_usage = "ENCRYPT_DECRYPT" }
  }
  expect_failures = [terraform_data.external_validation]
}

run "rejects_unorderable_instance_selection" {
  command = plan
  override_data {
    target = data.aws_rds_orderable_db_instance.selected
    values = { instance_class = "db.m5.large", engine = "aurora-postgresql", engine_version = "17.9", storage_type = "aurora" }
  }
  expect_failures = [terraform_data.external_validation]
}
```

- [ ] **Step 2: Run the discovery test to verify it fails**

Run:

```bash
terraform test -filter=tests/discovery.tftest.hcl
```

Expected: FAIL because the data sources and discovery locals do not exist.

- [ ] **Step 3: Add AWS context, KMS, security-group, role, and orderability lookups**

Create `data.tf`:

```hcl
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

data "aws_kms_key" "application" {
  key_id = var.kms_key_arn
}

data "aws_security_group" "allowed" {
  for_each = var.allowed_security_group_ids
  id       = each.value
}

locals {
  role_bindings = merge([
    for tier, arns in {
      runtime  = var.runtime_role_arns
      migrator = var.migrator_role_arns
      readonly = var.readonly_role_arns
      monitor  = var.monitor_role_arns
    } : {
      for arn in arns : arn => {
        tier          = tier
        arn           = arn
        role_name     = element(reverse(split("/", arn)), 0)
        database_user = "${tier}_${substr(sha256(arn), 0, 8)}"
      }
    }
  ]...)
}

data "aws_iam_role" "workload" {
  for_each = local.role_bindings
  name     = each.value.role_name
}

data "aws_rds_orderable_db_instance" "selected" {
  engine                     = local.engine_profile.aws_engine
  engine_version             = local.engine_profile.engine_version
  preferred_instance_classes = local.instance_class_candidates
  storage_type               = local.storage_type
  supported_engine_modes     = ["provisioned"]
  supports_clusters          = true
  supports_enhanced_monitoring = true
  supports_iam_database_authentication = true
  supports_performance_insights = true
  supports_storage_encryption = true
  vpc                        = true
}
```

The orderability lookup deliberately receives an ordered candidate list. It selects the preferred Graviton class when offered in the target partition/Region and falls back to the approved older family; an explicit override becomes a one-element list and therefore fails if unavailable.

- [ ] **Step 4: Implement versioned network and control-plane discovery**

Create `network.tf`:

```hcl
locals {
  network_parameter_name = "/platform/network/v1/${var.environment}/${var.stage}/${data.aws_region.current.name}/aurora"
}

data "aws_ssm_parameter" "network" {
  name = local.network_parameter_name
}

locals {
  network_contract = try(jsondecode(data.aws_ssm_parameter.network.value), {})
}

resource "terraform_data" "network_contract_shape" {
  input = data.aws_ssm_parameter.network.name

  lifecycle {
    precondition {
      condition = (
        try(local.network_contract.schema_version, null) == 1 &&
        try(length(local.network_contract.db_subnet_group_name) > 0, false)
      )
      error_message = "The network SSM parameter must contain schema_version=1 and db_subnet_group_name."
    }
  }
}

data "aws_db_subnet_group" "database" {
  name       = try(local.network_contract.db_subnet_group_name, "invalid-network-contract")
  depends_on = [terraform_data.network_contract_shape]
}

data "aws_subnet" "database" {
  for_each = toset(data.aws_db_subnet_group.database.subnet_ids)
  id       = each.value
}

data "aws_resourcegroupstaggingapi_resources" "database_subnet_group" {
  resource_type_filters = ["rds:subgrp"]

  tag_filter {
    key    = "Environment"
    values = [var.environment]
  }
  tag_filter {
    key    = "Stage"
    values = [var.stage]
  }
  tag_filter {
    key    = "Purpose"
    values = ["aurora"]
  }
}

locals {
  vpc_id      = data.aws_db_subnet_group.database.vpc_id
  database_azs = sort(distinct([for subnet in data.aws_subnet.database : subnet.availability_zone]))
  tagged_subnet_group_arns = toset([
    for mapping in data.aws_resourcegroupstaggingapi_resources.database_subnet_group.resource_tag_mapping_list : mapping.resource_arn
  ])
  control_plane_parameter_name = "/platform/database-access/v1/${var.environment}/${data.aws_region.current.name}/${local.vpc_id}/control-plane"
}

data "aws_ssm_parameter" "control_plane" {
  name = local.control_plane_parameter_name
}

locals {
  control_plane_contract = try(jsondecode(data.aws_ssm_parameter.control_plane.value), {})
}

resource "terraform_data" "control_plane_contract_shape" {
  input = data.aws_ssm_parameter.control_plane.name

  lifecycle {
    precondition {
      condition = (
        try(local.control_plane_contract.schema_version, null) == 1 &&
        try(length(local.control_plane_contract.dispatcher_function_name) > 0, false) &&
        try(length(local.control_plane_contract.dispatcher_qualifier) > 0, false) &&
        try(length(local.control_plane_contract.target_role_principal_arn) > 0, false) &&
        try(length(local.control_plane_contract.revision) > 0, false) &&
        try(can(regex("^sg-[0-9a-f]+$", local.control_plane_contract.security_group_id)), false)
      )
      error_message = "The database-access SSM parameter must contain a complete schema_version=1 control-plane contract."
    }
  }
}

data "aws_security_group" "control_plane" {
  id         = try(local.control_plane_contract.security_group_id, "sg-invalid")
  depends_on = [terraform_data.control_plane_contract_shape]
}

data "aws_lambda_function" "dispatcher" {
  function_name = try(local.control_plane_contract.dispatcher_function_name, "invalid-dispatcher")
  qualifier     = try(local.control_plane_contract.dispatcher_qualifier, "invalid")
  depends_on    = [terraform_data.control_plane_contract_shape]
}
```

- [ ] **Step 5: Add blocking external metadata preconditions**

Append one built-in validation resource to `checks.tf`:

```hcl
resource "terraform_data" "external_validation" {
  input = {
    network_parameter       = data.aws_ssm_parameter.network.name
    control_plane_parameter = data.aws_ssm_parameter.control_plane.name
    kms_key_arn             = data.aws_kms_key.application.arn
  }

  lifecycle {
    precondition {
      condition = (
        data.aws_db_subnet_group.database.status == "Complete" &&
        length(local.database_azs) >= 2 &&
        alltrue([for subnet in data.aws_subnet.database : subnet.vpc_id == local.vpc_id && subnet.state == "available"]) &&
        contains(local.tagged_subnet_group_arns, data.aws_db_subnet_group.database.arn)
      )
      error_message = "The discovered DB subnet group must be Complete, tagged for environment/stage/aurora, and span at least two available AZs in one VPC."
    }

    precondition {
      condition = (
        can(regex("^arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/", local.control_plane_contract.target_role_principal_arn)) &&
        can(regex("^arn:${data.aws_partition.current.partition}:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:", data.aws_lambda_function.dispatcher.arn)) &&
        data.aws_security_group.control_plane.vpc_id == local.vpc_id
      )
      error_message = "The database-access control plane must use a same-account worker and dispatcher attached to the discovered VPC."
    }

    precondition {
    condition = (
      data.aws_kms_key.application.arn == var.kms_key_arn &&
      data.aws_kms_key.application.enabled &&
      data.aws_kms_key.application.key_manager == "CUSTOMER" &&
      data.aws_kms_key.application.key_spec == "SYMMETRIC_DEFAULT" &&
      data.aws_kms_key.application.key_usage == "ENCRYPT_DECRYPT" &&
      can(regex("^arn:${data.aws_partition.current.partition}:kms:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:key/", data.aws_kms_key.application.arn))
    )
    error_message = "kms_key_arn must identify an enabled, symmetric, customer-managed key in this account and Region."
    }

    precondition {
      condition     = alltrue([for group in data.aws_security_group.allowed : group.vpc_id == local.vpc_id])
      error_message = "Every allowed security group must belong to the discovered database VPC."
    }

    precondition {
      condition = (
        contains(local.instance_class_candidates, data.aws_rds_orderable_db_instance.selected.instance_class) &&
        data.aws_rds_orderable_db_instance.selected.engine == local.engine_profile.aws_engine &&
        data.aws_rds_orderable_db_instance.selected.engine_version == local.engine_profile.engine_version &&
        data.aws_rds_orderable_db_instance.selected.storage_type == local.storage_type
      )
      error_message = "The selected instance class must be orderable for the engine version and storage profile in this Region."
    }

    precondition {
      condition = alltrue([
        for arn, role in data.aws_iam_role.workload : role.arn == arn && can(regex("^arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/", role.arn))
      ])
      error_message = "Every workload role must exist in the current account and match its supplied ARN."
    }

    precondition {
      condition     = length(distinct([for binding in values(local.role_bindings) : binding.database_user])) == length(local.role_bindings)
      error_message = "The generated database usernames must be unique across all supplied IAM roles."
    }
  }
}
```

- [ ] **Step 6: Document the external contract consumed by this repository**

Create `docs/contracts/database-access-control-plane-v1.md` with:

- The exact SSM paths and JSON shapes from the approved design.
- Required account, partition, Region, VPC, schema-version, and qualifier validation.
- The fact that `revision` triggers reconciliation.
- The CRUD lifecycle envelope injected under `tf`, including `action` and `prev_input`.
- The desired-state payload fields later defined in Task 6.
- Synchronous success semantics and the rule that no credential value appears in the contract.
- An ownership statement: this repository consumes the control plane but does not deploy it.

Include the literal control-plane discovery document:

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

- [ ] **Step 7: Run discovery and regression tests**

Run:

```bash
terraform fmt
terraform validate
terraform test -filter=tests/discovery.tftest.hcl
terraform test -filter=tests/validation.tftest.hcl
terraform test -filter=tests/policy-matrix.tftest.hcl
```

Expected: PASS. Update the valid runs in the older test files with the same external-data overrides so adding discovery does not turn policy tests into accidental AWS calls.

- [ ] **Step 8: Commit external discovery**

```bash
git add data.tf network.tf checks.tf tests/discovery.tftest.hcl tests/validation.tftest.hcl tests/policy-matrix.tftest.hcl docs/contracts/database-access-control-plane-v1.md
git commit -m "feat: discover and validate Aurora platform contracts"
```

---

### Task 4: Assemble Aurora, Recovery, and Protected Decommissioning

**Files:**
- Create: `recovery.tf`
- Create: `aurora.tf`
- Modify: `locals.tf`
- Modify: `checks.tf`
- Create: `tests/recovery.tftest.hcl`
- Modify: `tests/policy-matrix.tftest.hcl`

**Interfaces:**
- Consumes: Validated external metadata and policy locals from Tasks 2–3.
- Produces: `module.aurora`, `random_id.final_snapshot`, `local.restore_arguments`, cluster endpoints/resource ID/master-secret metadata, and resources required by IAM and dispatcher tasks.

- [ ] **Step 1: Write failing Aurora assembly and recovery tests**

Add plan assertions to `tests/policy-matrix.tftest.hcl` against the facade's normalized child-module configuration:

```hcl
assert {
  condition = (
    local.aurora_configuration.iam_database_authentication_enabled &&
    local.aurora_configuration.storage_encrypted
  )
  error_message = "Aurora must require IAM authentication and encrypted storage."
}
```

Use the normalized instance map for public accessibility:

```hcl
assert {
  condition     = alltrue([for instance in values(local.instances) : !instance.publicly_accessible])
  error_message = "Every Aurora instance must be private."
}
```

Create `tests/recovery.tftest.hcl` with deterministic AWS overrides and these runs:

- Snapshot restore with same account, Region, engine, and KMS key passes.
- Snapshot encrypted by a different KMS key fails `terraform_data.recovery_validation`.
- Snapshot from the wrong engine fails.
- Point-in-time latest restore sets `use_latest_restorable_time = true`.
- Point-in-time timestamp inside the window sets `restore_to_time`.
- Timestamp before `earliest_restorable_time` or after `latest_restorable_time` fails.
- Both modes retain the explicit desired `database_name`/`schema_name` contract for post-restore reconciliation.
- Recovery adds `target_suffix` to the physical cluster name and never reuses the source identifier.

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:

```bash
terraform test -filter=tests/recovery.tftest.hcl
terraform test -filter=tests/policy-matrix.tftest.hcl
```

Expected: FAIL because `module.aurora` and recovery data do not exist.

- [ ] **Step 3: Implement source discovery and restore arguments**

Create `recovery.tf`:

```hcl
data "aws_db_cluster_snapshot" "recovery" {
  count = try(var.recovery.mode, null) == "snapshot" ? 1 : 0

  db_cluster_snapshot_identifier = var.recovery.snapshot_identifier
}

data "aws_rds_cluster" "recovery" {
  count = try(var.recovery.mode, null) == "point-in-time" ? 1 : 0

  cluster_identifier = var.recovery.source_cluster_identifier
}

locals {
  snapshot_source = try(data.aws_db_cluster_snapshot.recovery[0], null)
  pitr_source     = try(data.aws_rds_cluster.recovery[0], null)

  restore_arguments = var.recovery == null ? {
    snapshot_identifier       = null
    restore_to_point_in_time  = null
  } : var.recovery.mode == "snapshot" ? {
    snapshot_identifier      = var.recovery.snapshot_identifier
    restore_to_point_in_time = null
  } : {
    snapshot_identifier = null
    restore_to_point_in_time = {
      source_cluster_identifier  = var.recovery.source_cluster_identifier
      source_cluster_resource_id = null
      restore_type               = "full-copy"
      restore_to_time            = var.recovery.restore_time
      use_latest_restorable_time = var.recovery.restore_time == null
    }
  }
}
```

Append a blocking recovery validation resource to `checks.tf`:

```hcl
resource "terraform_data" "recovery_validation" {
  input = var.recovery

  lifecycle {
    precondition {
      condition = var.recovery == null ? true : (
        var.recovery.mode == "snapshot" ? (
        local.snapshot_source.status == "available" &&
        local.snapshot_source.engine == local.engine_profile.aws_engine &&
        startswith(local.snapshot_source.engine_version, var.engine == "postgresql" ? "17." : "8.4.") &&
        local.snapshot_source.kms_key_id == var.kms_key_arn &&
        local.cluster_name != local.snapshot_source.db_cluster_identifier &&
        can(regex("^arn:${data.aws_partition.current.partition}:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:", local.snapshot_source.db_cluster_snapshot_arn))
        ) : (
          local.pitr_source.status == "available" &&
          local.pitr_source.engine == local.engine_profile.aws_engine &&
          startswith(local.pitr_source.engine_version, var.engine == "postgresql" ? "17." : "8.4.") &&
          local.pitr_source.kms_key_id == var.kms_key_arn &&
          local.cluster_name != local.pitr_source.cluster_identifier &&
          can(regex("^arn:${data.aws_partition.current.partition}:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:", local.pitr_source.arn)) &&
          (var.recovery.restore_time == null ? true : (
            timecmp(var.recovery.restore_time, local.pitr_source.earliest_restorable_time) >= 0 &&
            timecmp(var.recovery.restore_time, local.pitr_source.latest_restorable_time) <= 0
          ))
        )
      )
      error_message = "Recovery source must be available, same-account, same-Region, engine-compatible, recoverable at the requested time, and encrypted by kms_key_arn."
    }
  }
}
```

- [ ] **Step 4: Derive instance placement and a stable final-snapshot name**

Append to `locals.tf`:

```hcl
locals {
  selected_instance_class = data.aws_rds_orderable_db_instance.selected.instance_class
  instances = {
    for index in range(local.stage_profile.instance_count) : format("instance-%d", index + 1) => {
      identifier = length("${local.cluster_name}-instance-${index + 1}") <= 63 ? "${local.cluster_name}-instance-${index + 1}" : "${substr(local.cluster_name, 0, 54)}-${substr(sha256("${local.cluster_name}:instance:${index + 1}"), 0, 8)}"
      instance_class        = local.selected_instance_class
      availability_zone     = local.database_azs[index % length(local.database_azs)]
      promotion_tier        = index
      publicly_accessible   = false
      monitoring_interval   = local.stage_profile.monitoring_interval
      performance_insights_enabled          = true
      performance_insights_kms_key_id       = var.kms_key_arn
      performance_insights_retention_period = var.database_insights_mode == "advanced" ? 465 : 7
    }
  }
}
```

Create the stable suffix at the top of `aurora.tf`:

```hcl
resource "random_id" "final_snapshot" {
  byte_length = 4

  keepers = {
    cluster_name = local.cluster_name
  }
}

locals {
  final_snapshot_identifier = local.stage_profile.skip_final_snapshot ? null : "${local.cluster_name}-final-${random_id.final_snapshot.hex}"
  raw_monitoring_role_name  = "${local.cluster_name}-monitoring"
  monitoring_role_name      = length(local.raw_monitoring_role_name) <= 64 ? local.raw_monitoring_role_name : "${substr(local.cluster_name, 0, 55)}-${substr(sha256(local.raw_monitoring_role_name), 0, 8)}"
  aurora_configuration = {
    iam_database_authentication_enabled = true
    storage_encrypted                   = true
    storage_type                        = local.storage_type
    backup_retention_period             = local.stage_profile.backup_retention
    deletion_protection                 = local.stage_profile.deletion_protection
    skip_final_snapshot                 = local.stage_profile.skip_final_snapshot
    final_snapshot_identifier           = local.final_snapshot_identifier
    apply_immediately                   = local.apply_immediately
    database_insights_mode              = var.database_insights_mode
    performance_insights_retention      = local.performance_insights_retention
    enabled_cloudwatch_logs_exports     = local.log_exports
    cloudwatch_log_retention            = local.stage_profile.log_retention
  }
}
```

- [ ] **Step 5: Invoke the exact official Aurora module**

Append to `aurora.tf`:

```hcl
module "aurora" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "10.3.1"

  name           = local.cluster_name
  engine         = local.engine_profile.aws_engine
  engine_mode    = "provisioned"
  engine_version = local.engine_profile.engine_version
  engine_lifecycle_support = "open-source-rds-extended-support-disabled"

  database_name   = var.recovery == null ? var.database_name : null
  master_username = var.recovery == null ? local.engine_profile.master_username : null
  manage_master_user_password  = true
  master_user_secret_kms_key_id = var.kms_key_arn

  create_db_subnet_group = false
  db_subnet_group_name   = data.aws_db_subnet_group.database.name
  vpc_id                 = local.vpc_id

  create_security_group = true
  security_group_name   = local.cluster_name
  security_group_ingress_rules = merge(
    {
      for id in var.allowed_security_group_ids : "application-${substr(sha256(id), 0, 8)}" => {
        description                  = "Application access to ${local.cluster_name}"
        from_port                    = local.engine_profile.port
        to_port                      = local.engine_profile.port
        ip_protocol                  = "tcp"
        referenced_security_group_id = id
      }
    },
    {
      control-plane = {
        description                  = "Database access-control reconciliation"
        from_port                    = local.engine_profile.port
        to_port                      = local.engine_profile.port
        ip_protocol                  = "tcp"
        referenced_security_group_id = data.aws_security_group.control_plane.id
      }
    }
  )
  security_group_egress_rules = {}

  iam_database_authentication_enabled = local.aurora_configuration.iam_database_authentication_enabled
  storage_encrypted                   = local.aurora_configuration.storage_encrypted
  kms_key_id                          = var.kms_key_arn
  storage_type                        = local.aurora_configuration.storage_type

  instances = local.instances
  serverlessv2_scaling_configuration = var.compute_mode == "serverless" ? local.serverless_scaling : null

  backup_retention_period      = local.aurora_configuration.backup_retention_period
  copy_tags_to_snapshot        = true
  delete_automated_backups     = true
  deletion_protection          = local.aurora_configuration.deletion_protection
  skip_final_snapshot          = local.aurora_configuration.skip_final_snapshot
  final_snapshot_identifier    = local.aurora_configuration.final_snapshot_identifier
  preferred_backup_window      = local.preferred_backup_window
  preferred_maintenance_window = local.preferred_maintenance_window
  apply_immediately            = local.aurora_configuration.apply_immediately
  auto_minor_version_upgrade   = false
  allow_major_version_upgrade  = false

  snapshot_identifier       = local.restore_arguments.snapshot_identifier
  restore_to_point_in_time  = local.restore_arguments.restore_to_point_in_time

  cluster_parameter_group = {
    name            = "${local.cluster_name}-cluster"
    use_name_prefix = true
    family          = local.engine_profile.parameter_family
    parameters      = local.cluster_parameters
  }
  db_parameter_group = {
    name            = "${local.cluster_name}-instance"
    use_name_prefix = true
    family          = local.engine_profile.parameter_family
    parameters      = local.instance_parameters
  }

  create_monitoring_role       = true
  iam_role_name                = local.monitoring_role_name
  iam_role_use_name_prefix     = false
  database_insights_mode       = local.aurora_configuration.database_insights_mode
  cluster_performance_insights_enabled          = true
  cluster_performance_insights_kms_key_id       = var.kms_key_arn
  cluster_performance_insights_retention_period = local.aurora_configuration.performance_insights_retention

  enabled_cloudwatch_logs_exports        = local.aurora_configuration.enabled_cloudwatch_logs_exports
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = local.aurora_configuration.cloudwatch_log_retention
  cloudwatch_log_group_kms_key_id         = var.kms_key_arn

  tags = local.canonical_tags
}
```

Do not set `availability_zones` at the cluster level: Aurora chooses its distributed storage AZs, while the explicit instance map guarantees distinct staging/prod instance placement without producing the two-AZ/three-AZ drift described by the upstream module.

- [ ] **Step 6: Verify profile, recovery, and decommission behavior**

Run:

```bash
terraform fmt
terraform validate
terraform test -filter=tests/policy-matrix.tftest.hcl
terraform test -filter=tests/recovery.tftest.hcl
```

Expected: PASS. Confirm the prod run sees deletion protection true; the prod `decommission = true` run sees deletion protection false while `skip_final_snapshot` remains false; dev/test runs skip final snapshots.

- [ ] **Step 7: Commit Aurora assembly**

```bash
git add recovery.tf aurora.tf locals.tf checks.tf tests/recovery.tftest.hcl tests/policy-matrix.tftest.hcl
git commit -m "feat: deploy protected Aurora profiles"
```

---

### Task 5: Create Deterministic IAM Database Identities and Exact Connect Policies

**Files:**
- Create: `iam.tf`
- Create: `tests/iam.tftest.hcl`
- Modify: `locals.tf`

**Interfaces:**
- Consumes: `local.role_bindings`, the validated control-plane worker principal, and `module.aurora.cluster_resource_id`.
- Produces: `local.reconciler_username`, `aws_iam_role.database_access_target`, `aws_iam_role_policy.reconciler_connect`, and one `aws_iam_role_policy.workload_connect` per supplied application role.

- [ ] **Step 1: Write failing IAM-policy tests**

Create `tests/iam.tftest.hcl`. Reuse the happy-path discovery overrides, override the child module so no Aurora resources are needed, and inspect decoded policy JSON:

```hcl
override_module {
  target = module.aurora
  outputs = {
    cluster_id                 = "commercial-prod-orders"
    cluster_arn                = "arn:aws:rds:us-east-1:123456789012:cluster:commercial-prod-orders"
    cluster_resource_id        = "cluster-ABCDEFGHIJKLMNOP"
    cluster_endpoint           = "commercial-prod-orders.cluster-example.us-east-1.rds.amazonaws.com"
    cluster_reader_endpoint    = "commercial-prod-orders.cluster-ro-example.us-east-1.rds.amazonaws.com"
    cluster_engine_version_actual = "17.9"
    cluster_master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!cluster-example" }]
    cluster_instances          = {}
    security_group_id          = "sg-0database123456789"
    db_cluster_cloudwatch_log_groups = {}
  }
}

run "runtime_policy_is_exact" {
  command = plan

  assert {
    condition = jsondecode(
      aws_iam_role_policy.workload_connect["arn:aws:iam::123456789012:role/orders-api"].policy
    ).Statement[0] == {
      Action   = "rds-db:connect"
      Effect   = "Allow"
      Resource = "arn:aws:rds-db:us-east-1:123456789012:dbuser:cluster-ABCDEFGHIJKLMNOP/runtime_${substr(sha256("arn:aws:iam::123456789012:role/orders-api"), 0, 8)}"
    }
    error_message = "Runtime policy must allow exactly one generated user on one cluster resource ID."
  }
}

run "target_role_trusts_only_control_plane_worker" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.database_access_target.assume_role_policy).Statement[0].Principal.AWS == "arn:aws:iam::123456789012:role/database-access-worker"
    error_message = "Target role trust must contain only the discovered worker principal."
  }
}
```

Add assertions that:

- Every database user is `<tier>_<eight lowercase hex characters>`.
- Two different role ARNs produce different users.
- The reconciler username is unchanged when only `recovery.target_suffix` changes.
- Target-role permanent permissions contain only `rds-db:connect` for the reconciler user.
- No permanent target-role statement contains `secretsmanager`, `kms`, `iam:PutRolePolicy`, or `iam:DeleteRolePolicy`.
- Each workload role receives its own exact user ARN, not a wildcard.

- [ ] **Step 2: Run the IAM tests to verify they fail**

Run:

```bash
terraform test -filter=tests/iam.tftest.hcl
```

Expected: FAIL because the IAM resources and reconciler username do not exist.

- [ ] **Step 3: Derive the stable reconciler identity**

Append to `locals.tf`:

```hcl
locals {
  permission_boundary_id = "${data.aws_caller_identity.current.account_id}:${data.aws_region.current.name}:${var.environment}:${var.stage}:${var.name}:${var.database_name}"
  reconciler_username    = "reconciler_${substr(sha256(local.permission_boundary_id), 0, 8)}"
  raw_target_role_name   = "${local.cluster_name}-database-access"
  target_role_name       = length(local.raw_target_role_name) <= 64 ? local.raw_target_role_name : "${substr(local.cluster_name, 0, 55)}-${substr(sha256(local.raw_target_role_name), 0, 8)}"
}
```

The boundary identifier intentionally excludes the recovery target suffix and physical cluster ID. A restored database can therefore attempt its existing IAM reconciler before using the master secret.

- [ ] **Step 4: Create the per-deployment target role and permanent reconciler permission**

Create the first half of `iam.tf`:

```hcl
data "aws_iam_policy_document" "database_access_target_trust" {
  statement {
    sid     = "ControlPlaneAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.control_plane_contract.target_role_principal_arn]
    }
  }
}

resource "aws_iam_role" "database_access_target" {
  name                 = local.target_role_name
  assume_role_policy   = data.aws_iam_policy_document.database_access_target_trust.json
  max_session_duration = 3600
  description          = "Application-scoped IAM database-access reconciliation for ${local.cluster_name}"
  tags                 = local.canonical_tags
}

data "aws_iam_policy_document" "reconciler_connect" {
  statement {
    sid       = "ConnectAsReconciler"
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = [
      "arn:${data.aws_partition.current.partition}:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${module.aurora.cluster_resource_id}/${local.reconciler_username}"
    ]
  }
}

resource "aws_iam_role_policy" "reconciler_connect" {
  name   = "database-reconciler-connect"
  role   = aws_iam_role.database_access_target.name
  policy = data.aws_iam_policy_document.reconciler_connect.json
}
```

Do not grant permanent Secrets Manager or KMS access. The external cleanup workflow owns the temporary bootstrap policy and the session-revocation policy update.

- [ ] **Step 5: Attach exact connect policies to supplied workload roles**

Append to `iam.tf`:

```hcl
data "aws_iam_policy_document" "workload_connect" {
  for_each = local.role_bindings

  statement {
    sid     = "ConnectAs${title(each.value.tier)}"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = [
      "arn:${data.aws_partition.current.partition}:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${module.aurora.cluster_resource_id}/${each.value.database_user}"
    ]
  }
}

resource "aws_iam_role_policy" "workload_connect" {
  for_each = local.role_bindings

  name   = "${local.cluster_name}-${each.value.tier}-database-connect"
  role   = data.aws_iam_role.workload[each.key].name
  policy = data.aws_iam_policy_document.workload_connect[each.key].json
}
```

- [ ] **Step 6: Run IAM and policy regression tests**

Run:

```bash
terraform fmt
terraform validate
terraform test -filter=tests/iam.tftest.hcl
terraform test -filter=tests/validation.tftest.hcl
```

Expected: PASS with no wildcard resource and no secret/KMS action in permanent role policies.

- [ ] **Step 7: Commit IAM access**

```bash
git add iam.tf locals.tf tests/iam.tftest.hcl
git commit -m "feat: add deterministic IAM database access"
```

---

### Task 6: Register the Database with the Shared Access Control Plane

**Files:**
- Create: `access-control.tf`
- Modify: `checks.tf`
- Create: `tests/access-control.tftest.hcl`
- Modify: `docs/contracts/database-access-control-plane-v1.md`

**Interfaces:**
- Consumes: Ready Aurora metadata, RDS-managed secret ARN, target role ARN, deterministic user mappings, engine/database/schema contract, dispatcher function/qualifier/revision.
- Produces: `local.database_access_contract`, `local.database_access_contract_hash`, `aws_lambda_invocation.database_access`, and a blocking success postcondition.

- [ ] **Step 1: Write failing payload and lifecycle tests**

Create `tests/access-control.tftest.hcl`. Reuse deterministic external-data and child-module overrides, then override the invocation result:

```hcl
override_resource {
  target = aws_lambda_invocation.database_access
  values = {
    result = jsonencode({
      status             = "SUCCEEDED"
      operation_id       = "op-12345678"
      desired_state_hash = local.database_access_contract_hash
    })
  }
}

run "payload_contains_only_desired_state" {
  command = plan

  assert {
    condition     = local.database_access_contract.schema_version == 1
    error_message = "Access payload must be schema version 1."
  }
  assert {
    condition     = local.database_access_contract.database == { name = "ordersdb", schema = "orders" }
    error_message = "Payload must preserve the explicit PostgreSQL logical contract."
  }
  assert {
    condition     = aws_lambda_invocation.database_access.lifecycle_scope == "CRUD"
    error_message = "Dispatcher invocation must cover create, update, and delete."
  }
  assert {
    condition     = aws_lambda_invocation.database_access.triggers.control_plane_revision == "2026-08-01.1"
    error_message = "Published control-plane revisions must trigger reconciliation."
  }
  assert {
    condition = alltrue([
      for forbidden in ["password", "secret_value", "auth_token", "connection_string"] :
      !strcontains(lower(jsonencode(local.database_access_contract)), forbidden)
    ])
    error_message = "Invocation payload must not contain credential-bearing fields."
  }
}
```

Add runs for MySQL `schema = null`, role addition/removal changing the desired-state hash, control-plane revision changing only the revision trigger, recovery payloads, stable sorted principal ordering, cluster-instance endpoints, and an unsuccessful result failing the invocation postcondition.

- [ ] **Step 2: Run the access-control test to verify it fails**

Run:

```bash
terraform test -filter=tests/access-control.tftest.hcl
```

Expected: FAIL because the desired-state contract and invocation do not exist.

- [ ] **Step 3: Build one versioned, deterministic desired-state object**

Create the first half of `access-control.tf`:

```hcl
locals {
  master_secret_arn = try(module.aurora.cluster_master_user_secret[0].secret_arn, null)

  database_access_desired_state = {
    schema_version = 1
    boundary_id    = local.permission_boundary_id
    environment    = var.environment
    stage          = var.stage

    cluster = {
      identifier       = module.aurora.cluster_id
      arn              = module.aurora.cluster_arn
      resource_id      = module.aurora.cluster_resource_id
      writer_endpoint  = module.aurora.cluster_endpoint
      reader_endpoint  = module.aurora.cluster_reader_endpoint
      instance_endpoints = sort([
        for instance in values(module.aurora.cluster_instances) : instance.endpoint
      ])
      port           = local.engine_profile.port
      engine         = local.engine_profile.aws_engine
      engine_version = module.aurora.cluster_engine_version_actual
    }

    database = {
      name   = var.database_name
      schema = var.engine == "postgresql" ? var.schema_name : null
    }

    bootstrap = {
      master_secret_arn = local.master_secret_arn
      kms_key_arn       = var.kms_key_arn
      target_role_arn   = aws_iam_role.database_access_target.arn
      reconciler_user   = local.reconciler_username
    }

    principals = [
      for arn in sort(keys(local.role_bindings)) : {
        iam_role_arn = arn
        database_user = local.role_bindings[arn].database_user
        tier          = local.role_bindings[arn].tier
      }
    ]

    recovery = var.recovery == null ? null : {
      mode          = var.recovery.mode
      target_suffix = local.recovery_suffix
    }
  }

  database_access_contract_hash = sha256(jsonencode(local.database_access_desired_state))
  database_access_contract = merge(local.database_access_desired_state, {
    desired_state_hash = local.database_access_contract_hash
  })
}
```

The hash covers the canonical desired state before the hash field is added, avoiding a self-reference while making the accepted hash explicit in the payload. The payload contains a master-secret ARN because the one-time bootstrap workflow needs to identify the secret. It must never contain the secret value.

- [ ] **Step 4: Invoke the dispatcher for create, update, and delete**

Append to `access-control.tf`:

```hcl
resource "aws_lambda_invocation" "database_access" {
  function_name   = local.control_plane_contract.dispatcher_function_name
  qualifier       = local.control_plane_contract.dispatcher_qualifier
  lifecycle_scope = "CRUD"
  terraform_key   = "tf"
  input           = jsonencode(local.database_access_contract)

  triggers = {
    desired_state_hash     = local.database_access_contract_hash
    control_plane_revision = local.control_plane_contract.revision
  }

  depends_on = [
    module.aurora,
    aws_iam_role_policy.reconciler_connect,
    aws_iam_role_policy.workload_connect,
    terraform_data.external_validation,
    terraform_data.recovery_validation
  ]

  lifecycle {
    postcondition {
      condition = (
        try(jsondecode(self.result).status, null) == "SUCCEEDED" &&
        try(jsondecode(self.result).desired_state_hash, null) == local.database_access_contract_hash
      )
      error_message = "The database-access control plane did not confirm reconciliation for the requested desired-state hash."
    }
  }
}

locals {
  database_access_result = jsondecode(aws_lambda_invocation.database_access.result)
}
```

The external dispatcher contract must throw a Lambda invocation error for workflow failures and return `status = "SUCCEEDED"` with the accepted desired-state hash only after IAM authentication and permissions are verified. Terraform's reverse dependency order causes the delete invocation to run before IAM and Aurora dependencies are destroyed.

- [ ] **Step 5: Complete the contract document**

Update `docs/contracts/database-access-control-plane-v1.md` with the exact object above, the required success result, the injected `tf.action` values (`create`, `update`, `delete`), `tf.prev_input`, idempotency by boundary/hash/action, the sub-15-minute dispatcher timeout, and the rule that the durable Standard Step Functions execution may continue after a caller timeout.

Document target-side expectations:

- First attempt IAM reconciliation using `reconciler_user`.
- If absent and bootstrap incomplete, attach the expiring temporary policy, read only the named secret, create the IAM reconciler, verify IAM, rotate the master password, remove temporary access, revoke older sessions, and record completion.
- PostgreSQL creates the database/schema roles and grants; MySQL creates the database roles and grants.
- Application migrations are never executed.
- Delete unregisters the boundary and revokes database identities idempotently.

Record the fixed authorization matrix literally:

| Tier | PostgreSQL | MySQL |
|---|---|---|
| Owner | Non-login owner of the application database/schema objects. | Non-login MySQL role holding boundary-scoped DDL/DML privileges; MySQL has no PostgreSQL-style object ownership. |
| Migrator | IAM login with `rds_iam`; may `SET ROLE` to owner inside the application boundary, with no user administration. | IAM user using `AWSAuthenticationPlugin`; granted the owner role only on `<database_name>.*`, with no user administration. |
| Runtime | IAM login with database `CONNECT`, schema `USAGE`, current/future table `SELECT, INSERT, UPDATE, DELETE`, sequence usage, and routine execution. | IAM user using `AWSAuthenticationPlugin`; current/future DML and routine execution only on `<database_name>.*`. |
| Readonly | IAM login with database `CONNECT`, schema `USAGE`, current/future table `SELECT`, and routine execution. | IAM user using `AWSAuthenticationPlugin`; `SELECT` and routine execution only on `<database_name>.*`. |
| Monitor | IAM login with the minimum engine statistics/query-observability grants listed by the control-plane compatibility profile. | IAM user using `AWSAuthenticationPlugin` with the minimum performance-schema/query-observability grants listed by the control-plane compatibility profile. |
| Reconciler | IAM-only privileged login scoped to maintaining this application database/schema contract. | IAM-only privileged user scoped to maintaining this application database contract. |

Require PostgreSQL reconciliation to revoke `PUBLIC` database/schema privileges and set owner default privileges for future tables, sequences, and routines. Require the temporary inline policy to use the exact name `database-bootstrap-secret-access`, name only `bootstrap.master_secret_arn`, permit KMS decrypt only for `bootstrap.kms_key_arn` through Secrets Manager, contain an absolute expiry, and be removed before success or failure is returned. State that exact temporary-policy unit tests belong to the separately owned control-plane implementation; this facade verifies the contract through the forced-failure integration job.

- [ ] **Step 6: Run lifecycle, IAM, and leak tests**

Run:

```bash
terraform fmt
terraform validate
terraform test -filter=tests/access-control.tftest.hcl
terraform test -filter=tests/iam.tftest.hcl
```

Expected: PASS. The unsuccessful-result run must fail only the declared `aws_lambda_invocation.database_access` postcondition.

- [ ] **Step 7: Commit access-control registration**

```bash
git add access-control.tf checks.tf tests/access-control.tftest.hcl docs/contracts/database-access-control-plane-v1.md
git commit -m "feat: reconcile database access synchronously"
```

---

### Task 7: Publish Stable, Non-Credential Outputs

**Files:**
- Create: `outputs.tf`
- Create: `tests/outputs.tftest.hcl`

**Interfaces:**
- Consumes: Aurora, discovery, IAM, and reconciliation metadata from Tasks 3–6.
- Produces: Stable `connection`, `database_users`, cluster/instance/security/logging identifiers, master-secret ARN, KMS ARN, desired-state hash, and reconciliation evidence.

- [ ] **Step 1: Write failing output-shape tests**

Create `tests/outputs.tftest.hcl` using the common deterministic overrides:

```hcl
run "postgres_connection_shape" {
  command = apply

  assert {
    condition = output.connection == {
      writer_endpoint = "commercial-prod-orders.cluster-example.us-east-1.rds.amazonaws.com"
      reader_endpoint = "commercial-prod-orders.cluster-ro-example.us-east-1.rds.amazonaws.com"
      port            = 5432
      database_name   = "ordersdb"
      schema_name     = "orders"
      ssl_mode        = "verify-full"
    }
    error_message = "PostgreSQL connection output shape changed unexpectedly."
  }
}
```

Add a MySQL run asserting `schema_name = null`, one run asserting the exact IAM-role-to-database-user map, and a recursive JSON scan proving no output key contains `password`, `token`, `secret_value`, or `connection_string`.

- [ ] **Step 2: Run the output tests to verify they fail**

Run:

```bash
terraform test -filter=tests/outputs.tftest.hcl
```

Expected: FAIL with undeclared outputs.

- [ ] **Step 3: Create the stable connection and identity outputs**

Create the first half of `outputs.tf`:

```hcl
output "connection" {
  description = "Stable non-credential connection contract."
  value = {
    writer_endpoint = module.aurora.cluster_endpoint
    reader_endpoint = module.aurora.cluster_reader_endpoint
    port            = local.engine_profile.port
    database_name   = var.database_name
    schema_name     = var.engine == "postgresql" ? var.schema_name : null
    ssl_mode        = local.engine_profile.ssl_mode
  }
}

output "database_users" {
  description = "IAM role ARN to deterministic database-login mapping by permission tier."
  value = {
    for tier in ["runtime", "migrator", "readonly", "monitor"] : tier => {
      for arn, binding in local.role_bindings : arn => binding.database_user if binding.tier == tier
    }
  }
}
```

- [ ] **Step 4: Add operational outputs without credential values**

Append to `outputs.tf`:

```hcl
output "cluster" {
  description = "Aurora cluster identifiers."
  value = {
    identifier     = module.aurora.cluster_id
    arn            = module.aurora.cluster_arn
    resource_id    = module.aurora.cluster_resource_id
    engine_version = module.aurora.cluster_engine_version_actual
  }
}

output "instances" {
  description = "Aurora instance identifiers and endpoints."
  value = {
    for key, instance in module.aurora.cluster_instances : key => {
      identifier = instance.identifier
      endpoint   = instance.endpoint
      az         = instance.availability_zone
    }
  }
}

output "network" {
  description = "Discovered and created network identifiers."
  value = {
    vpc_id               = local.vpc_id
    db_subnet_group_name = data.aws_db_subnet_group.database.name
    security_group_id    = module.aurora.security_group_id
  }
}

output "log_group_arns" {
  description = "CloudWatch database log-group ARNs."
  value = {
    for name, group in module.aurora.db_cluster_cloudwatch_log_groups : name => group.arn
  }
}

output "master_secret_arn" {
  description = "RDS-managed master-secret ARN for separately authorized break-glass tooling."
  value       = local.master_secret_arn
}

output "kms_key_arn" {
  description = "Application-specific KMS key used by this deployment."
  value       = var.kms_key_arn
}

output "access_reconciliation" {
  description = "Desired-state hash and successful reconciliation evidence."
  value = {
    desired_state_hash = local.database_access_contract_hash
    operation_id       = local.database_access_result.operation_id
    status             = local.database_access_result.status
  }
  depends_on = [aws_lambda_invocation.database_access]
}
```

- [ ] **Step 5: Run output and full mocked tests**

Run:

```bash
terraform fmt
terraform validate
terraform test
```

Expected: PASS with zero failed runs. Confirm the MySQL output retains the stable field `schema_name = null`.

- [ ] **Step 6: Commit outputs**

```bash
git add outputs.tf tests/outputs.tftest.hcl
git commit -m "feat: expose the ready Aurora connection contract"
```

---

### Task 8: Add Developer Examples and Operational Documentation

**Files:**
- Create: `examples/postgres-serverless/main.tf`
- Create: `examples/postgres-serverless/variables.tf`
- Create: `examples/postgres-serverless/outputs.tf`
- Create: `examples/mysql-provisioned/main.tf`
- Create: `examples/mysql-provisioned/variables.tf`
- Create: `examples/mysql-provisioned/outputs.tf`
- Create: `docs/operations/recovery.md`
- Create: `docs/operations/decommission.md`
- Create: `.terraform-docs.yml`
- Create: `scripts/validate-examples.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: The finalized public inputs and outputs.
- Produces: Copyable consumer compositions, recovery/decommission runbooks, and a stakeholder-readable module README with generated reference tables.

- [ ] **Step 1: Write the failing example-validation harness**

Create executable `scripts/validate-examples.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

for example_dir in examples/postgres-serverless examples/mysql-provisioned; do
  test -d "${example_dir}"
  terraform -chdir="${example_dir}" init -backend=false
  terraform -chdir="${example_dir}" validate
done

rg -q 'schema_name[[:space:]]*=' examples/postgres-serverless/main.tf
if rg -q 'schema_name[[:space:]]*=' examples/mysql-provisioned/main.tf; then
  printf 'MySQL example must not pass schema_name\n' >&2
  exit 1
fi
```

- [ ] **Step 2: Run example validation to verify it fails**

Run:

```bash
scripts/validate-examples.sh
```

Expected: FAIL on the first `test -d` because both example directories are absent.

- [ ] **Step 3: Create the minimal PostgreSQL serverless example**

Create `examples/postgres-serverless/main.tf`:

```hcl
terraform {
  required_version = ">= 1.11.1, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.54, < 7.0"
    }
  }
}

module "database" {
  source = "../.."

  name          = "orders"
  environment   = var.environment
  stage         = var.stage
  database_name = "ordersdb"
  schema_name   = "orders"
  kms_key_arn   = var.kms_key_arn

  allowed_security_group_ids = var.allowed_security_group_ids
  runtime_role_arns           = var.runtime_role_arns
  migrator_role_arns          = var.migrator_role_arns
}
```

Create the same `variables.tf` in each example directory:

```hcl
variable "environment" {
  type = string
}

variable "stage" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "allowed_security_group_ids" {
  type = set(string)
}

variable "runtime_role_arns" {
  type = set(string)
}

variable "migrator_role_arns" {
  type = set(string)
}
```

Create `examples/postgres-serverless/outputs.tf`:

```hcl
output "connection" {
  value = module.database.connection
}

output "database_users" {
  value = module.database.database_users
}
```

- [ ] **Step 4: Create the minimal MySQL provisioned example**

Create `examples/mysql-provisioned/main.tf`:

```hcl
terraform {
  required_version = ">= 1.11.1, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.54, < 7.0"
    }
  }
}

module "database" {
  source = "../.."

  name          = "orders"
  environment   = var.environment
  stage         = var.stage
  engine        = "mysql"
  compute_mode  = "provisioned"
  size          = "medium"
  database_name = "ordersdb"
  kms_key_arn   = var.kms_key_arn

  allowed_security_group_ids = var.allowed_security_group_ids
  runtime_role_arns           = var.runtime_role_arns
  migrator_role_arns          = var.migrator_role_arns
}
```

Use the exact `variables.tf` block from Step 3. Create `examples/mysql-provisioned/outputs.tf`:

```hcl
output "connection" {
  value = module.database.connection
}

output "database_users" {
  value = module.database.database_users
}
```

Do not declare or pass `schema_name` in the MySQL example.

- [ ] **Step 5: Write recovery and decommission runbooks**

Create `docs/operations/recovery.md` with:

- Normal creation versus snapshot versus point-in-time input examples.
- Source restrictions: same account, Region, engine profile, and KMS key.
- New-cluster naming and the optional `target_suffix`.
- The rule that application cutover and source retirement are outside this module.
- A verification checklist covering reconciliation status, database/schema identity, application IAM login, monitoring, backups, and cutover ownership.
- The requirement to copy and re-encrypt a snapshot externally before restore if the KMS key must change.

Create `docs/operations/decommission.md` with this literal protected workflow:

```hcl
module "database" {
  # Existing staging/prod configuration remains present.
  decommission = true
}
```

Document:

1. Apply the preparation change while the module remains in configuration.
2. Verify deletion protection changed to false and the database remains present.
3. Review the separate removal plan.
4. Apply removal; access unregisters first and Aurora creates the unique final snapshot.
5. Verify the final snapshot and retain the external application KMS key.

State explicitly that removing a protected module without step 1 is rejected by AWS at apply time. Dev/test skip this preparation and final snapshot by design.

- [ ] **Step 6: Replace the one-line README with the product contract**

Rewrite `README.md` with these sections in order:

1. What this module provides.
2. Ten-line PostgreSQL/serverless quick start.
3. Supported engines, compute modes, sizes, and stage behavior table.
4. Required platform contracts and ownership diagram.
5. Authentication and fixed permission tiers.
6. Recovery and decommission links.
7. Observability and backup boundaries.
8. Unsupported capabilities and exception policy.
9. Generated requirements, providers, inputs, outputs, and resources markers.

Use terraform-docs markers:

```markdown
<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
```

Create `.terraform-docs.yml`:

```yaml
formatter: markdown table
output:
  file: README.md
  mode: inject
settings:
  anchor: true
  color: false
  default: true
  description: true
  escape: false
  hide-empty: true
  html: true
  indent: 2
  lockfile: false
  read-comments: true
  required: true
  sensitive: true
  type: true
```

- [ ] **Step 7: Generate documentation and validate examples**

Run:

```bash
terraform-docs --config .terraform-docs.yml .
terraform fmt -recursive -check
terraform validate
scripts/validate-examples.sh
```

Expected: PASS and a second `terraform-docs --config .terraform-docs.yml .` produces no Git diff.

- [ ] **Step 8: Commit examples and operations documentation**

```bash
git add README.md .terraform-docs.yml examples docs/operations scripts/validate-examples.sh
git commit -m "docs: add Aurora usage and operations guides"
```

---

### Task 9: Add CI, Real-AWS Integration Tests, and Release Gates

**Files:**
- Create: `.tflint.hcl`
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/integration.yml`
- Create: `tests/integration/main.tf`
- Create: `tests/integration/variables.tf`
- Create: `tests/integration/outputs.tf`
- Create: `tests/integration/README.md`
- Create: `scripts/run-integration.sh`
- Create: `scripts/run-failure-integration.sh`

**Interfaces:**
- Consumes: The complete module, dedicated AWS test-account fixtures, and a real shared database-access control plane.
- Produces: Pull-request quality gates plus manual/scheduled evidence for creation, reconciliation, recovery, idempotency, and deletion.

- [ ] **Step 1: Run the failing release-gate presence test**

Run:

```bash
test -f .tflint.hcl
test -f .github/workflows/ci.yml
test -f .github/workflows/integration.yml
test -f scripts/run-integration.sh
```

Expected: FAIL on `test -f .tflint.hcl`.

- [ ] **Step 2: Configure TFLint with exact plugin versions**

Create `.tflint.hcl`:

```hcl
config {
  call_module_type = "all"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.47.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
```

- [ ] **Step 3: Add pull-request CI**

Create `.github/workflows/ci.yml`:

```yaml
name: ci

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.15.8
      - uses: terraform-linters/setup-tflint@v6
        with:
          tflint_version: v0.62.0
      - name: Install terraform-docs
        run: |
          curl --fail --location --silent --show-error \
            --output terraform-docs.tar.gz \
            https://github.com/terraform-docs/terraform-docs/releases/download/v0.24.0/terraform-docs-v0.24.0-linux-amd64.tar.gz
          echo "9005daf969de0b50134493a2c00078b49f5f5b39d021cda7c89bf4d4f3d776d3  terraform-docs.tar.gz" | sha256sum --check
          tar -xzf terraform-docs.tar.gz terraform-docs
          sudo install terraform-docs /usr/local/bin/terraform-docs
      - run: terraform fmt -recursive -check
      - run: terraform init -backend=false
      - run: terraform validate
      - run: tflint --init
      - run: tflint --recursive
      - run: terraform test
      - run: terraform-docs --config .terraform-docs.yml .
      - run: git diff --exit-code -- README.md
```

- [ ] **Step 4: Create the real-AWS integration composition**

Create `tests/integration/variables.tf`:

```hcl
variable "environment" { type = string }
variable "stage" { type = string }
variable "engine" { type = string }
variable "compute_mode" { type = string }
variable "size" { type = string }
variable "kms_key_arn" { type = string }
variable "allowed_security_group_ids" { type = set(string) }
variable "runtime_role_arns" { type = set(string) }
variable "migrator_role_arns" { type = set(string) }

variable "recovery" {
  type = object({
    mode                      = string
    snapshot_identifier       = optional(string)
    source_cluster_identifier = optional(string)
    restore_time              = optional(string)
    target_suffix             = optional(string)
  })
  default = null
}

variable "decommission" {
  type    = bool
  default = false
}
```

Create `tests/integration/main.tf`:

```hcl
terraform {
  required_version = ">= 1.11.1, < 2.0"

  backend "s3" {}
}

module "subject" {
  source = "../.."

  name          = "aurora-integration"
  environment   = var.environment
  stage         = var.stage
  engine        = var.engine
  compute_mode  = var.compute_mode
  size          = var.size
  database_name = "integrationdb"
  schema_name   = var.engine == "postgresql" ? "integration" : null
  kms_key_arn   = var.kms_key_arn

  allowed_security_group_ids = var.allowed_security_group_ids
  runtime_role_arns           = var.runtime_role_arns
  migrator_role_arns          = var.migrator_role_arns
  recovery                    = var.recovery
  decommission                = var.decommission
}
```

Create `tests/integration/outputs.tf`:

```hcl
output "connection" {
  value = module.subject.connection
}

output "cluster" {
  value = module.subject.cluster
}

output "database_users" {
  value = module.subject.database_users
}

output "access_reconciliation" {
  value = module.subject.access_reconciliation
}
```

- [ ] **Step 5: Implement deterministic integration orchestration**

Create executable `scripts/run-integration.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${INTEGRATION_SCENARIO:?INTEGRATION_SCENARIO is required}"
: "${TF_BACKEND_BUCKET:?TF_BACKEND_BUCKET is required}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${TF_VAR_stage:?TF_VAR_stage is required}"
: "${TF_VAR_kms_key_arn:?TF_VAR_kms_key_arn is required}"

integration_dir="tests/integration"
state_key="aurora-module/${INTEGRATION_SCENARIO}.tfstate"
plan_file="${INTEGRATION_SCENARIO}.tfplan"
cleanup_required=false

cleanup() {
  trap - EXIT
  if [[ "${cleanup_required}" == "true" ]]; then
    set +e
    if [[ "${TF_VAR_stage}" == "staging" || "${TF_VAR_stage}" == "prod" ]]; then
      terraform -chdir="${integration_dir}" apply -auto-approve -var='decommission=true'
      terraform -chdir="${integration_dir}" destroy -auto-approve -var='decommission=true'
    else
      terraform -chdir="${integration_dir}" destroy -auto-approve
    fi
  fi
}
trap cleanup EXIT

terraform -chdir="${integration_dir}" init -reconfigure \
  -backend-config="bucket=${TF_BACKEND_BUCKET}" \
  -backend-config="key=${state_key}" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="use_lockfile=true"
cleanup_required=true

terraform -chdir="${integration_dir}" plan -out="${plan_file}"
terraform -chdir="${integration_dir}" apply "${plan_file}"

second_exit=0
terraform -chdir="${integration_dir}" plan -detailed-exitcode -out="second.tfplan" || second_exit=$?
test "${second_exit}" -eq 0

terraform -chdir="${integration_dir}" output -json access_reconciliation \
  | jq -e '.status == "SUCCEEDED" and (.desired_state_hash | length == 64)'

if [[ -n "${SECONDARY_RUNTIME_ROLE_ARN:-}" ]]; then
  original_runtime_roles="${TF_VAR_runtime_role_arns}"
  extended_runtime_roles=$(jq -cn \
    --argjson existing "${original_runtime_roles}" \
    --arg additional "${SECONDARY_RUNTIME_ROLE_ARN}" \
    '$existing + [$additional] | unique')

  terraform -chdir="${integration_dir}" apply -auto-approve \
    -var="runtime_role_arns=${extended_runtime_roles}"
  terraform -chdir="${integration_dir}" output -json database_users \
    | jq -e --arg arn "${SECONDARY_RUNTIME_ROLE_ARN}" '.runtime[$arn] | length > 0'

  terraform -chdir="${integration_dir}" apply -auto-approve \
    -var="runtime_role_arns=${original_runtime_roles}"
  terraform -chdir="${integration_dir}" output -json database_users \
    | jq -e --arg arn "${SECONDARY_RUNTIME_ROLE_ARN}" '.runtime[$arn] == null'
fi

if [[ -n "${EXPECTED_SOURCE_CLUSTER_ID:-}" ]]; then
  restored_cluster_id=$(terraform -chdir="${integration_dir}" output -json cluster | jq -r '.identifier')
  test "${restored_cluster_id}" != "${EXPECTED_SOURCE_CLUSTER_ID}"
fi

destroy_arguments=()
if [[ "${TF_VAR_stage}" == "staging" || "${TF_VAR_stage}" == "prod" ]]; then
  terraform -chdir="${integration_dir}" apply -auto-approve -var='decommission=true'
  destroy_arguments=(-var='decommission=true')
fi

cluster_state=$(terraform -chdir="${integration_dir}" show -json \
  | jq -ec '.. | objects | select(.address? == "module.subject.module.aurora.aws_rds_cluster.this[0]") | .values')
skip_final_snapshot=$(jq -r '.skip_final_snapshot' <<<"${cluster_state}")
final_snapshot_identifier=$(jq -r '.final_snapshot_identifier // empty' <<<"${cluster_state}")

if [[ "${TF_VAR_stage}" == "staging" || "${TF_VAR_stage}" == "prod" ]]; then
  test "${skip_final_snapshot}" = "false"
  test -n "${final_snapshot_identifier}"
else
  test "${skip_final_snapshot}" = "true"
  test -z "${final_snapshot_identifier}"
fi

terraform -chdir="${integration_dir}" destroy -auto-approve "${destroy_arguments[@]}"
cleanup_required=false

if [[ -n "${final_snapshot_identifier}" ]]; then
  aws rds describe-db-cluster-snapshots \
    --db-cluster-snapshot-identifier "${final_snapshot_identifier}" \
    | jq -e --arg key "${TF_VAR_kms_key_arn}" \
      '.DBClusterSnapshots[0] | .Status == "available" and .KmsKeyId == $key'
fi
```

The runner expects dedicated fixtures and environment variables supplied by the workflow; it never creates the shared network, control plane, or long-lived application KMS key inside the subject module. Snapshot and point-in-time workflow jobs set `TF_VAR_recovery` to the complete recovery object and `EXPECTED_SOURCE_CLUSTER_ID` to the source identifier, causing the runner to prove that recovery created a different physical cluster. The first baseline case sets `SECONDARY_RUNTIME_ROLE_ARN`, so the same runner also proves addition and independent revocation of a principal.

- [ ] **Step 6: Implement the expected-failure cleanup test**

Create executable `scripts/run-failure-integration.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${TF_BACKEND_BUCKET:?TF_BACKEND_BUCKET is required}"
: "${AWS_REGION:?AWS_REGION is required}"

integration_dir="tests/integration"
state_key="aurora-module/dispatcher-failure-cleanup.tfstate"
failure_log="${integration_dir}/failure-apply.log"
cleanup_required=false

cleanup() {
  trap - EXIT
  if [[ "${cleanup_required}" == "true" ]]; then
    set +e
    terraform -chdir="${integration_dir}" destroy -auto-approve
  fi
}
trap cleanup EXIT

terraform -chdir="${integration_dir}" init -reconfigure \
  -backend-config="bucket=${TF_BACKEND_BUCKET}" \
  -backend-config="key=${state_key}" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="use_lockfile=true"
cleanup_required=true

apply_exit=0
terraform -chdir="${integration_dir}" apply -auto-approve 2>&1 \
  | tee "${failure_log}" || apply_exit=${PIPESTATUS[0]}
test "${apply_exit}" -ne 0

target_role_name=$(terraform -chdir="${integration_dir}" show -json \
  | jq -er '.. | objects | select(.address? == "module.subject.aws_iam_role.database_access_target") | .values.name')

aws iam list-role-policies --role-name "${target_role_name}" \
  | jq -e '.PolicyNames | index("database-bootstrap-secret-access") == null'

terraform -chdir="${integration_dir}" destroy -auto-approve
cleanup_required=false
test -z "$(terraform -chdir="${integration_dir}" state list)"
```

The dedicated failure-test control-plane contract must point to a failure-injection dispatcher qualifier that adds its temporary bootstrap permission, forces the workflow to fail, waits for the cleanup branch to remove that permission, then returns an invocation error. Its delete action must remain idempotent and successful so Terraform can clean up the failed apply. This is a test fixture owned by the separate control-plane project, not a production escape hatch in this module.

- [ ] **Step 7: Add the approval-gated and scheduled integration workflow**

Create `.github/workflows/integration.yml`:

```yaml
name: integration

on:
  workflow_dispatch:
  schedule:
    - cron: "17 6 * * 1"

permissions:
  contents: read
  id-token: write

concurrency:
  group: aurora-module-integration
  cancel-in-progress: false

env:
  TF_IN_AUTOMATION: "true"

jobs:
  baseline:
    name: ${{ matrix.scenario }}
    runs-on: ubuntu-latest
    timeout-minutes: 120
    environment: aurora-integration
    strategy:
      fail-fast: false
      matrix:
        include:
          - scenario: postgresql-serverless-dev
            engine: postgresql
            compute_mode: serverless
            stage: dev
            size: small
            role_lifecycle: true
          - scenario: postgresql-provisioned-prod
            engine: postgresql
            compute_mode: provisioned
            stage: prod
            size: small
            role_lifecycle: false
          - scenario: mysql-serverless-dev
            engine: mysql
            compute_mode: serverless
            stage: dev
            size: small
            role_lifecycle: false
          - scenario: mysql-provisioned-prod
            engine: mysql
            compute_mode: provisioned
            stage: prod
            size: small
            role_lifecycle: false
    env:
      AWS_REGION: ${{ vars.INTEGRATION_AWS_REGION }}
      TF_BACKEND_BUCKET: ${{ vars.INTEGRATION_TF_BACKEND_BUCKET }}
      INTEGRATION_SCENARIO: ${{ matrix.scenario }}
      TF_VAR_environment: ${{ vars.INTEGRATION_ENVIRONMENT }}
      TF_VAR_stage: ${{ matrix.stage }}
      TF_VAR_engine: ${{ matrix.engine }}
      TF_VAR_compute_mode: ${{ matrix.compute_mode }}
      TF_VAR_size: ${{ matrix.size }}
      TF_VAR_kms_key_arn: ${{ vars.INTEGRATION_KMS_KEY_ARN }}
      TF_VAR_allowed_security_group_ids: ${{ vars.INTEGRATION_ALLOWED_SECURITY_GROUP_IDS_JSON }}
      TF_VAR_runtime_role_arns: ${{ vars.INTEGRATION_RUNTIME_ROLE_ARNS_JSON }}
      TF_VAR_migrator_role_arns: ${{ vars.INTEGRATION_MIGRATOR_ROLE_ARNS_JSON }}
      SECONDARY_RUNTIME_ROLE_ARN: ${{ matrix.role_lifecycle && vars.INTEGRATION_SECONDARY_RUNTIME_ROLE_ARN || '' }}
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.15.8
      - uses: aws-actions/configure-aws-credentials@v5
        with:
          role-to-assume: ${{ vars.INTEGRATION_AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
      - name: Create, reconcile, re-plan, and destroy
        run: |
          chmod +x scripts/run-integration.sh
          scripts/run-integration.sh

  recovery:
    name: recovery-${{ matrix.mode }}
    needs: baseline
    runs-on: ubuntu-latest
    timeout-minutes: 120
    environment: aurora-integration
    strategy:
      fail-fast: false
      matrix:
        include:
          - mode: snapshot
            scenario: postgresql-snapshot-recovery
            target_suffix: snapshot-it
          - mode: point-in-time
            scenario: postgresql-pitr-recovery
            target_suffix: pitr-it
    env:
      AWS_REGION: ${{ vars.INTEGRATION_AWS_REGION }}
      TF_BACKEND_BUCKET: ${{ vars.INTEGRATION_TF_BACKEND_BUCKET }}
      INTEGRATION_SCENARIO: ${{ matrix.scenario }}
      TF_VAR_environment: ${{ vars.INTEGRATION_ENVIRONMENT }}
      TF_VAR_stage: test
      TF_VAR_engine: postgresql
      TF_VAR_compute_mode: serverless
      TF_VAR_size: small
      TF_VAR_kms_key_arn: ${{ vars.INTEGRATION_KMS_KEY_ARN }}
      TF_VAR_allowed_security_group_ids: ${{ vars.INTEGRATION_ALLOWED_SECURITY_GROUP_IDS_JSON }}
      TF_VAR_runtime_role_arns: ${{ vars.INTEGRATION_RUNTIME_ROLE_ARNS_JSON }}
      TF_VAR_migrator_role_arns: ${{ vars.INTEGRATION_MIGRATOR_ROLE_ARNS_JSON }}
      EXPECTED_SOURCE_CLUSTER_ID: ${{ vars.INTEGRATION_RECOVERY_SOURCE_CLUSTER_ID }}
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.15.8
      - uses: aws-actions/configure-aws-credentials@v5
        with:
          role-to-assume: ${{ vars.INTEGRATION_AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
      - name: Build recovery input
        env:
          RECOVERY_MODE: ${{ matrix.mode }}
          TARGET_SUFFIX: ${{ matrix.target_suffix }}
          SNAPSHOT_IDENTIFIER: ${{ vars.INTEGRATION_RECOVERY_SNAPSHOT_IDENTIFIER }}
          SOURCE_CLUSTER_ID: ${{ vars.INTEGRATION_RECOVERY_SOURCE_CLUSTER_ID }}
          RESTORE_TIME: ${{ vars.INTEGRATION_RECOVERY_RESTORE_TIME }}
        run: |
          if [[ "${RECOVERY_MODE}" == "snapshot" ]]; then
            recovery=$(jq -cn \
              --arg snapshot "${SNAPSHOT_IDENTIFIER}" \
              --arg suffix "${TARGET_SUFFIX}" \
              '{mode:"snapshot", snapshot_identifier:$snapshot, target_suffix:$suffix}')
          else
            recovery=$(jq -cn \
              --arg source "${SOURCE_CLUSTER_ID}" \
              --arg restore_time "${RESTORE_TIME}" \
              --arg suffix "${TARGET_SUFFIX}" \
              '{mode:"point-in-time", source_cluster_identifier:$source, target_suffix:$suffix}
               + if $restore_time == "" then {} else {restore_time:$restore_time} end')
          fi
          printf 'TF_VAR_recovery=%s\n' "${recovery}" >> "${GITHUB_ENV}"
      - name: Restore, reconcile, re-plan, and destroy
        run: |
          chmod +x scripts/run-integration.sh
          scripts/run-integration.sh

  dispatcher-failure-cleanup:
    needs: baseline
    runs-on: ubuntu-latest
    timeout-minutes: 90
    environment: aurora-integration-failure
    env:
      AWS_REGION: ${{ vars.INTEGRATION_AWS_REGION }}
      TF_BACKEND_BUCKET: ${{ vars.INTEGRATION_TF_BACKEND_BUCKET }}
      TF_VAR_environment: ${{ vars.INTEGRATION_FAILURE_ENVIRONMENT }}
      TF_VAR_stage: dev
      TF_VAR_engine: postgresql
      TF_VAR_compute_mode: serverless
      TF_VAR_size: small
      TF_VAR_kms_key_arn: ${{ vars.INTEGRATION_KMS_KEY_ARN }}
      TF_VAR_allowed_security_group_ids: ${{ vars.INTEGRATION_ALLOWED_SECURITY_GROUP_IDS_JSON }}
      TF_VAR_runtime_role_arns: ${{ vars.INTEGRATION_RUNTIME_ROLE_ARNS_JSON }}
      TF_VAR_migrator_role_arns: ${{ vars.INTEGRATION_MIGRATOR_ROLE_ARNS_JSON }}
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.15.8
      - uses: aws-actions/configure-aws-credentials@v5
        with:
          role-to-assume: ${{ vars.INTEGRATION_AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
      - name: Prove failure propagation and temporary-policy cleanup
        run: |
          chmod +x scripts/run-failure-integration.sh
          scripts/run-failure-integration.sh
      - name: Upload expected-failure evidence
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: dispatcher-failure-log
          path: tests/integration/failure-apply.log
          if-no-files-found: error
          retention-days: 14
```

Configure required reviewers on the `aurora-integration` and `aurora-integration-failure` GitHub environments. Store only non-secret fixture identifiers in environment variables; use OpenID Connect rather than static AWS credentials.

- [ ] **Step 8: Document integration-account prerequisites and evidence**

Create `tests/integration/README.md` listing:

- Dedicated account and Region.
- Published network and control-plane SSM contracts.
- External application KMS key protected from deletion.
- Existing runtime/migrator roles and source security group.
- GitHub OpenID Connect deployment role.
- Versioned remote state bucket with S3 native lockfiles enabled.
- Budget and automatic cleanup alerting.
- Evidence captured per run: plans, reconciliation result, IAM login verification, restore identifiers, final snapshot identifier, and cleanup outcome.

State that release integration runs are cost-bearing and that an unchanged second plan is mandatory evidence of idempotency.

- [ ] **Step 9: Run all local gates**

Run:

```bash
terraform fmt -recursive -check
terraform init -backend=false
terraform validate
tflint --init
tflint --recursive
terraform test
terraform-docs --config .terraform-docs.yml .
git diff --exit-code -- README.md
git diff --check
```

Expected: every command exits zero and `terraform test` reports zero failed runs.

- [ ] **Step 10: Commit CI and integration infrastructure**

```bash
git add .tflint.hcl .github/workflows/ci.yml .github/workflows/integration.yml tests/integration scripts/run-integration.sh scripts/run-failure-integration.sh
git commit -m "test: add Aurora module release gates"
```

---

### Task 10: Perform the Release-Candidate Audit

**Files:**
- Modify: only files required to resolve audit findings
- Review: every file listed in this plan

**Interfaces:**
- Consumes: The complete implementation from Tasks 1–9.
- Produces: A clean release candidate with traceable design coverage and fresh verification evidence.

- [ ] **Step 1: Audit every approved design section against implementation**

Create a temporary review checklist outside the repository and map each design heading to code and tests:

- Public contract and engine-specific logical names.
- Stage, compute, size, storage, version, monitoring, and backup profiles.
- Network discovery and VPC derivation.
- External application KMS key.
- Security-group-only ingress.
- Deterministic role mapping and exact IAM policies.
- One-time bootstrap and ongoing reconciliation contract.
- Recovery restrictions.
- Two-apply protected decommissioning.
- Stable non-credential outputs.
- Mocked and real-AWS tests.

Expected: every item maps to at least one implementation file and one automated test or integration scenario.

- [ ] **Step 2: Search for prohibited escape hatches and credential fields**

Run:

```bash
rg -n 'cidr|publicly_accessible\s*=\s*true|master_password|secret_value|auth_token|connection_string|local-exec|remote-exec|cloudformation|aws_cloudformation' --glob '*.tf' --glob '*.md' .
```

Expected: matches exist only in negative tests, explicit prohibitions, AWS field documentation, or the non-secret `master_secret_arn` name. Inspect every match and remove any credential-bearing or implementation escape hatch.

- [ ] **Step 3: Run the complete fresh verification suite**

Run:

```bash
terraform fmt -recursive -check
terraform init -backend=false -upgrade=false
terraform validate
tflint --init
tflint --recursive
terraform test -verbose
terraform-docs --config .terraform-docs.yml .
git diff --exit-code -- README.md
git diff --check
git status --short
```

Expected: every command exits zero, all test runs pass, generated documentation is stable, and only intentional release-candidate changes appear in `git status`.

- [ ] **Step 4: Run the approval-gated AWS release suite**

Trigger `.github/workflows/integration.yml` in the dedicated test environment. Require green evidence for the four baseline profiles, snapshot restore, point-in-time restore, idempotent second apply, role addition and independent revocation, disposable dev deletion, protected prod preparation/final-snapshot deletion, and dispatcher-failure cleanup.

- [ ] **Step 5: Commit audit corrections when present**

If Steps 1–4 required code changes, stage only those corrections and commit:

```bash
git add versions.tf variables.tf checks.tf locals.tf data.tf network.tf parameters.tf recovery.tf aurora.tf iam.tf access-control.tf outputs.tf tests examples docs README.md .tflint.hcl .terraform-docs.yml .github scripts
git commit -m "fix: resolve Aurora release audit findings"
```

If no corrections were required, do not create an empty commit. Record the verification command outputs in the pull-request description.
