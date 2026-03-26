provider "aws" {
  region = var.aws_region

  # default_tags are automatically applied to every resource in this layer.
  # Individual resources only need to declare Name and Purpose on top.
  default_tags {
    tags = merge(
      var.tags,
      {
        Project   = var.project_name
        ManagedBy = "terraform-bootstrap"
        Layer     = "bootstrap"
        Owner     = var.owner
      }
    )
  }
}
