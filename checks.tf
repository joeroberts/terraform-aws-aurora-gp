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
