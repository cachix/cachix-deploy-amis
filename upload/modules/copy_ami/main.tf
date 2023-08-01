terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "ami" {
  type = object({
    id       = string
    name     = string
    tags_all = map(string)
  })
  description = "The AMI to copy"
}

variable "source_region" {
  type        = string
  description = "The region the AMI is in"
}

data "aws_region" "target_region" {
  provider = aws
}

locals {
  target_region = data.aws_region.target_region.name
  release       = var.ami.tags_all.Release
  system        = var.ami.tags_all.System
}

resource "aws_ami_copy" "cachix-deploy-ami" {
  provider          = aws
  name              = var.ami.name
  source_ami_id     = var.ami.id
  source_ami_region = var.source_region
  tags = {
    Release = local.release
    System  = local.system
  }
}

locals {
  new_ami = aws_ami_copy.cachix-deploy-ami
}

output "ami" {
  value = { "${local.release}.${local.target_region}.${local.system}" = local.new_ami.id }
}
