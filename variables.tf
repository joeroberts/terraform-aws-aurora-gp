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
