# IAM Module - Roles and Policies
# Creates IAM roles with configurable assume role policies and permissions

# ==========================================
# IAM Role
# ==========================================
resource "aws_iam_role" "this" {
  name               = var.role_name
  description        = var.role_description
  assume_role_policy = var.assume_role_policy

  max_session_duration  = var.max_session_duration
  force_detach_policies = var.force_detach_policies
  path                  = var.path

  tags = merge(var.tags, {
    Name = var.role_name
  })
}

# ==========================================
# Managed Policy Attachments
# ==========================================
resource "aws_iam_role_policy_attachment" "managed" {
  count = length(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = var.managed_policy_arns[count.index]
}

# ==========================================
# Inline Policies
# ==========================================
resource "aws_iam_role_policy" "inline" {
  for_each = var.inline_policies

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}

# ==========================================
# Custom Managed Policies (Optional)
# ==========================================
resource "aws_iam_policy" "custom" {
  for_each = var.custom_policies

  name        = each.key
  description = lookup(each.value, "description", "Custom policy for ${var.role_name}")
  policy      = each.value.policy

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "custom" {
  for_each = aws_iam_policy.custom

  role       = aws_iam_role.this.name
  policy_arn = each.value.arn
}
