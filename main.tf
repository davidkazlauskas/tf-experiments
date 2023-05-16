module "label" {
  source  = "cloudposse/label/null"
  version = "0.25.0"

  attributes = ["cluster"]

  context = module.this.context
}

locals {
  # The usage of the specific kubernetes.io/cluster/* resource tags below are required
  # for EKS and Kubernetes to discover and manage networking resources
  # https://aws.amazon.com/premiumsupport/knowledge-center/eks-vpc-subnet-discovery/
  # https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/main/docs/deploy/subnet_discovery.md
  tags = { "kubernetes.io/cluster/${module.label.id}" = "shared" }

  # required tags to make ALB ingress work https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html
  public_subnets_additional_tags = {
    "kubernetes.io/role/elb" : 1
  }
  private_subnets_additional_tags = {
    "kubernetes.io/role/internal-elb" : 1
  }
}

module "main_vpc" {
  source  = "cloudposse/vpc/aws"
  version = "1.1.0"

  cidr_block = var.main_vpc_cidr
  tags       = local.tags

  context = module.this.context
}

module "subnets" {
  source  = "cloudposse/dynamic-subnets/aws"
  version = "2.0.2"

  availability_zones              = var.availability_zones
  vpc_id                          = module.main_vpc.vpc_id
  igw_id                          = [module.main_vpc.igw_id]
  ipv4_cidr_block                 = [module.main_vpc.vpc_cidr_block]
  nat_gateway_enabled             = true
  nat_instance_enabled            = false
  tags                            = local.tags
  public_subnets_additional_tags  = local.public_subnets_additional_tags
  private_subnets_additional_tags = local.private_subnets_additional_tags
  ipv6_enabled                    = false

  context = module.this.context
}

module "eks_cluster" {
  source  = "cloudposse/eks-cluster/aws"
  version = "2.6.0"

  region                       = var.region
  vpc_id                       = module.main_vpc.vpc_id
  subnet_ids                   = concat(module.subnets.private_subnet_ids, module.subnets.public_subnet_ids)
  kubernetes_version           = var.kubernetes_version
  local_exec_interpreter       = var.local_exec_interpreter
  oidc_provider_enabled        = var.oidc_provider_enabled
  enabled_cluster_log_types    = var.enabled_cluster_log_types
  cluster_log_retention_period = var.cluster_log_retention_period

  cluster_encryption_config_enabled                         = var.cluster_encryption_config_enabled
  cluster_encryption_config_kms_key_id                      = var.cluster_encryption_config_kms_key_id
  cluster_encryption_config_kms_key_enable_key_rotation     = var.cluster_encryption_config_kms_key_enable_key_rotation
  cluster_encryption_config_kms_key_deletion_window_in_days = var.cluster_encryption_config_kms_key_deletion_window_in_days
  cluster_encryption_config_kms_key_policy                  = var.cluster_encryption_config_kms_key_policy
  cluster_encryption_config_resources                       = var.cluster_encryption_config_resources

  addons = var.addons

  create_security_group = false

  allowed_security_group_ids = [module.main_vpc.vpc_default_security_group_id]
  allowed_cidr_blocks        = [var.all_vpc_cidr]

  context = module.this.context
}

module "eks_node_group" {
  source  = "cloudposse/eks-node-group/aws"
  version = "2.4.0"

  subnet_ids        = module.subnets.private_subnet_ids
  cluster_name      = module.eks_cluster.eks_cluster_id
  instance_types    = var.instance_types
  desired_size      = var.desired_size
  min_size          = var.min_size
  max_size          = var.max_size
  kubernetes_labels = var.kubernetes_labels

  # Prevent the node groups from being created before the Kubernetes aws-auth ConfigMap
  module_depends_on = module.eks_cluster.kubernetes_config_map_id

  context = module.this.context
}

module "alb_ingress_controller" {
  source  = "lablabs/eks-load-balancer-controller/aws"
  version = "1.2.0"

  cluster_name                     = module.eks_cluster.eks_cluster_id
  cluster_identity_oidc_issuer     = module.eks_cluster.eks_cluster_identity_oidc_issuer
  cluster_identity_oidc_issuer_arn = module.eks_cluster.eks_cluster_identity_oidc_issuer_arn
}

data "aws_ecr_authorization_token" "token" {}

module "poller_ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "1.6.0"
  repository_name                 = "gopoller"
  # for running few times in development
  repository_image_tag_mutability = "MUTABLE"
  repository_lifecycle_policy     = file("${path.module}/ecr-lifecycle-policy.json")
  repository_type                 = "private"
  repository_force_delete         = true
}

locals {
  image_version = "v1.0.1"
}

resource "null_resource" "docker_packaging" {
  provisioner "local-exec" {
    command = <<EOF
    docker login ${data.aws_ecr_authorization_token.token.proxy_endpoint} \
      -u AWS -p ${data.aws_ecr_authorization_token.token.password}
    cd ${path.module}/go-app
    export IMAGE_NAME=${module.poller_ecr.repository_url}
    export VERSION=${local.image_version}
    make \
      IMAGE_NAME=$IMAGE_NAME \
      VERSION=$VERSION \
      build
    docker push "$IMAGE_NAME:$VERSION"
    EOF
  }

  depends_on = [
    module.poller_ecr.repository_url,
  ]
}

resource "helm_release" "service0" {
  name       = "service0"
  chart      = "${path.module}/go-app/chart"

  values = [
    file("${path.module}/helm-vals/service0-values.yaml")
  ]

  set {
    name = "image.version"
    value = "${local.image_version}"
  }

  set {
    name = "image.repository"
    value = "${module.poller_ecr.repository_url}"
  }
}

resource "helm_release" "service1" {
  name       = "service1"
  chart      = "${path.module}/go-app/chart"

  values = [
    file("${path.module}/helm-vals/service1-values.yaml")
  ]

  set {
    name = "image.version"
    value = "${local.image_version}"
  }

  set {
    name = "image.repository"
    value = "${module.poller_ecr.repository_url}"
  }
}
