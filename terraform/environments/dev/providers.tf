provider "aws" {
  region = var.aws_region

  # Applied to every resource this configuration creates that supports
  # tags, so nothing needs to repeat Project/Environment/ManagedBy by hand.
  default_tags {
    tags = local.common_tags
  }
}
