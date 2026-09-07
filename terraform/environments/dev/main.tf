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
