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
}

output ami_id {
  value = aws_ami_copy.cachix-deploy-ami.id
}
