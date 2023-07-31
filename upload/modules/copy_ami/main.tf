terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "ami" {
  type = object({
    id   = string
    name = string
    tags_all = map(string)
  })
  description = "The AMI to copy"
}

variable "source_region" {
  type = string
  description = "The region the AMI is in"
}

resource "aws_ami_copy" "cachix-deploy-ami" {
  provider          = aws
  name              = var.ami.name
  source_ami_id     = var.ami.id
  source_ami_region = var.source_region
  tags = {
    System = var.ami.tags_all.System
  }
}

output id {
  value = aws_ami_copy.cachix-deploy-ami.id
}
