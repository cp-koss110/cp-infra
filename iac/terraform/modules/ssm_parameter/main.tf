# SSM Parameter Module - Secure Parameter Storage
# Creates SSM parameters with encryption support

# ==========================================
# SSM Parameter
# ==========================================
resource "aws_ssm_parameter" "this" {
  name        = var.parameter_name
  description = var.description
  type        = var.parameter_type
  value       = var.parameter_value
  tier        = var.tier

  # KMS encryption for SecureString
  key_id = var.parameter_type == "SecureString" ? var.kms_key_id : null

  # Data type (for advanced parameters)
  data_type = var.data_type

  # Overwrite existing parameter
  overwrite = var.overwrite

  # Allowed pattern (validation)
  allowed_pattern = var.allowed_pattern

  tags = merge(var.tags, {
    Name = var.parameter_name
  })
}
