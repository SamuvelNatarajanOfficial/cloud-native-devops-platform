# --------------------------------------------------------------------------
# State backend
# --------------------------------------------------------------------------
# Local state is used by default (no backend block below) so this project
# can be cloned and run with zero pre-existing AWS resources - no bucket
# or lock table has to exist before `terraform init` works. terraform.tfstate
# is gitignored and never committed either way (see ../../../.gitignore).
#
# For team use, or to run `terraform plan`/`apply` from CI, move to a
# remote backend instead: create an S3 bucket (versioned, encrypted) and a
# DynamoDB table for locking out of band, then uncomment and fill in the
# block below before running `terraform init` again (Terraform will offer
# to migrate the existing local state for you).
#
# terraform {
#   backend "s3" {
#     bucket         = "REPLACE_ME-taskflow-tfstate"
#     key            = "dev/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "REPLACE_ME-taskflow-tf-locks"
#     encrypt        = true
#   }
# }
