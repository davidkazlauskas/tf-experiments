region = "us-east-1"

availability_zones = ["us-east-1a", "us-east-1b"]

all_vpc_cidr = "10.16.0.0/15"
main_vpc_cidr = "10.16.0.0/16"
lambda_vpc_cidr = "10.17.0.0/16"

namespace = "eg"

stage = "test"

name = "eks"

# When updating the Kubernetes version, also update the API and client-go version in test/src/go.mod
kubernetes_version = "1.22"

oidc_provider_enabled = true

enabled_cluster_log_types = ["audit"]

cluster_log_retention_period = 7

instance_types = ["t3.small"]

desired_size = 2

max_size = 3

min_size = 2

kubernetes_labels = {}

cluster_encryption_config_enabled = true

addons = [
  {
    addon_name               = "vpc-cni"
    addon_version            = null
    resolve_conflicts        = "NONE"
    service_account_role_arn = null
  }
]
