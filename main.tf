variable "release" {
  type        = string
  default     = "stable"
  description = "NixOS version to use: stable or unstable."
}

variable "region" {
  type        = string
  default     = ""
  description = "AWS region to use. If not provided, current provider's region will be used."
}

data "aws_region" "current" {}

locals {
  amis = jsondecode(file("${path.module}/amis.json"))
  key = "${var.release}.${coalesce(var.region, data.aws_region.current.name)}"
}

output "id" {
  description = "Cachix Deploy AMI"
  value       = amis[local.key]
}
