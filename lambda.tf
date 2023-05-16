module "lambda_vpc" {
  source  = "cloudposse/vpc/aws"
  version = "1.1.0"

  cidr_block = var.lambda_vpc_cidr
  tags       = local.tags

  context = module.this.context
}

module "lambda_subnets" {
  source  = "cloudposse/dynamic-subnets/aws"
  version = "2.0.2"

  availability_zones              = var.availability_zones
  vpc_id                          = module.lambda_vpc.vpc_id
  igw_id                          = [module.lambda_vpc.igw_id]
  ipv4_cidr_block                 = [module.lambda_vpc.vpc_cidr_block]
  nat_gateway_enabled             = false
  nat_instance_enabled            = false
  ipv6_enabled                    = false

  context = module.this.context
}

module "vpc_peering" {
  source  = "cloudposse/vpc-peering/aws"
  version = "0.10.0"

  auto_accept                               = true
  requestor_allow_remote_vpc_dns_resolution = true
  acceptor_allow_remote_vpc_dns_resolution  = true
  requestor_vpc_id                          = module.lambda_vpc.vpc_id
  acceptor_vpc_id                           = module.main_vpc.vpc_id
  requestor_ignore_cidrs                    = []

  create_timeout                            = "5m"
  update_timeout                            = "5m"
  delete_timeout                            = "10m"

  context = module.this.context

  # enable after apply
  enabled = true
}

data "kubernetes_nodes" "lambda_target_nodes" {}

# get ip addresses from hostnames
locals {
  lambda_target_nodes = [
    for node in data.kubernetes_nodes.lambda_target_nodes.nodes :
      replace(trim(split(".", node.metadata.0.name)[0], "ip-"), "-", ".")
  ]
}

resource "null_resource" "lambda_packaging" {
  provisioner "local-exec" {
    command = <<EOF
    cd ${path.module}/lambda
    # would be a lot of work to resolve dns to k8s worker
    # nodes so we simply query information from terraform
    # and hardcode ip in code
    cat lambda_function.py.tpl | \
      sed 's/EKS_WORKER_IP/${local.lambda_target_nodes[0]}/g' > \
      lambda_function.py
    zip lambda-function.zip lambda_function.py
    rm lambda_function.py
    EOF
  }

  depends_on = [
    module.poller_ecr.repository_url,
  ]
}

module "lambda_access_secgroup" {
  source  = "cloudposse/security-group/aws"
  version = "2.0.1"

  vpc_id                       = module.lambda_vpc.vpc_id

  rules_map = merge({ dns-cidr = [
    {
      key                      = "egress"
      type                     = "egress"
      from_port                = 30701 # our node port in eks cluster that exposes allowed service
      to_port                  = 30701
      protocol                 = "tcp"
      cidr_blocks              = [var.main_vpc_cidr]
    }] })
}

module "lambda" {
  source  = "cloudposse/lambda-function/aws"
  version = "0.4.1"

  function_name = "poll"
  filename      = "${path.module}/lambda/lambda-function.zip"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.10"

  vpc_config = {
    subnet_ids = module.lambda_subnets.private_subnet_ids,
    security_group_ids = [
      module.lambda_access_secgroup.id,
    ]
  }
}
