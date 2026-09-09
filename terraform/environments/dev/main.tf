locals {
  # Used as the base name for the cluster and as a prefix for every
  # resource name/Name tag, so dev/staging/prod resources never collide
  # if they ever share an AWS account.
  name_prefix = "${var.cluster_name}-${var.environment}"

  common_tags = merge(var.tags, {
    Project     = "taskflow"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# --------------------------------------------------------------------------
# Networking
# --------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  name_prefix        = local.name_prefix
  cluster_name       = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  azs                = var.availability_zones
  single_nat_gateway = var.single_nat_gateway
  tags               = local.common_tags
}

# --------------------------------------------------------------------------
# IAM roles for the cluster and its worker nodes
# --------------------------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

# --------------------------------------------------------------------------
# EKS cluster + managed node group
# --------------------------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.name_prefix
  kubernetes_version = var.kubernetes_version

  cluster_role_arn = module.iam.cluster_role_arn
  node_role_arn    = module.iam.node_role_arn

  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids

  endpoint_public_access = var.eks_endpoint_public_access
  public_access_cidrs    = var.eks_public_access_cidrs

  node_instance_types = var.node_instance_types
  capacity_type       = var.node_capacity_type
  desired_size        = var.desired_node_count
  min_size            = var.min_node_count
  max_size            = var.max_node_count

  tags = local.common_tags
}

# --------------------------------------------------------------------------
# Phase 6: IRSA role for the AWS Load Balancer Controller
#
# Reuses the OIDC provider the eks module above already registers - no new
# OIDC provider, no IAM user, no long-lived access key. This role sits
# unused (and free) until a real controller is actually installed and
# configured to assume it via its ServiceAccount's
# eks.amazonaws.com/role-arn annotation - see
# networking/aws-load-balancer-controller/values-dev.yaml and
# argocd/application-dev-aws-load-balancer-controller.yaml. Creating an
# unused IAM role has no cost and no blast radius (it can't be assumed by
# anything except the exact ServiceAccount named below), so - unlike the
# dns module - this is instantiated unconditionally rather than gated
# behind a toggle.
# --------------------------------------------------------------------------
module "aws_load_balancer_controller_irsa" {
  source = "../../modules/irsa"

  role_name            = "${local.name_prefix}-aws-load-balancer-controller"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_issuer_url      = module.eks.cluster_oidc_issuer_url
  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"
  # The official policy AWS publishes for this exact controller version -
  # fetched verbatim from
  # https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.5.0/docs/install/iam_policy.json,
  # not reconstructed by hand. Re-fetch this file (and bump the pinned
  # version comment) if networking/aws-load-balancer-controller's own
  # pinned version ever changes - see that chart's values file.
  policy_json = file("${path.module}/policies/aws-load-balancer-controller-iam-policy.json")

  tags = local.common_tags
}

# --------------------------------------------------------------------------
# Phase 6: DNS / ACM - see this environment's enable_dns variable and
# terraform/modules/dns/main.tf's own header comment for why this is off
# by default.
# --------------------------------------------------------------------------
module "dns" {
  count  = var.enable_dns ? 1 : 0
  source = "../../modules/dns"

  domain_name        = var.domain_name
  create_hosted_zone = var.create_hosted_zone
  tags               = local.common_tags
}
