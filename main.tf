variable "release" {
  type        = string
  default     = "stable"
  description = "NixOS version to use: stable or unstable."

  validation {
    condition     = contains(["stable", "unstable"], var.release)
    error_message = "Invalid release: ${var.release}. Must be stable or unstable."
  }
}

variable "system" {
  type        = string
  default     = "x86_64-linux"
  description = "System to use: x86_64-linux or aarch64-linux."

  validation {
    condition     = contains(["x86_64-linux", "aarch64-linux"], var.system)
    error_message = "Invalid system: ${var.system}. Must be x86_64-linux or aarch64-linux."
  }
}

variable "region" {
  type        = string
  default     = ""
  description = "AWS region to use. If not provided, current provider's region will be used."
}

data "aws_region" "current" {}

locals {
  amis = jsondecode(file("${path.module}/amis.json"))
  key = "${var.release}.${coalesce(var.region, data.aws_region.current.name)}.${var.system}"
}

output "id" {
  description = "Cachix Deploy AMI"
  value       = local.amis[local.key]
}
