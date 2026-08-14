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
