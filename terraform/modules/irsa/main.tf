# --------------------------------------------------------------------------
# A generic IRSA (IAM Roles for Service Accounts) role: trusts exactly one
# Kubernetes ServiceAccount (namespace + name), via the OIDC provider the
# eks module (Phase 2) already registers - no new OIDC provider is created
# here, and no IAM user or long-lived access key is ever involved. Reusable
# for any future controller/workload that needs its own scoped AWS
# permissions (this project's first consumer is the AWS Load Balancer
# Controller - see terraform/environments/dev/main.tf), rather than a
# one-off module tied to a single controller's name.
# --------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    # Restricts assumption to exactly one ServiceAccount identity - not
    # "any pod in this cluster", and not "any ServiceAccount named X in
    # any cluster that happens to share this AWS account's trust". Both
    # condition keys are required together: `aud` alone would let any
    # ServiceAccount in the cluster assume the role; `sub` alone (without
    # this OIDC provider's own audience restriction) is the well-known
    # IRSA trust-policy mistake this project deliberately avoids.
    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.role_name}-policy"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}
