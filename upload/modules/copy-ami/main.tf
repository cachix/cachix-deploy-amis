terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws",
      configuration_aliases = [
        aws.ap-northeast-1,
        aws.ap-south-1
      ]
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

resource "aws_ami_copy" "cachix-deploy-ami-ap-south-1" {
  provider          = aws.ap-south-1
  name              = var.ami.name
  source_ami_id     = var.ami.id
  source_ami_region = var.source_region
}

resource "aws_ami_copy" "cachix-deploy-ami-ap-northeast-1" {
  provider          = aws.ap-northeast-1
  name              = var.ami.name
  source_ami_id     = var.ami.id
  source_ami_region = var.source_region
}
