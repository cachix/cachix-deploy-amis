terraform {
  cloud {
    organization = "cachix"

    workspaces {
      # TODO: which workspace?
      name = "cachix-deploy-amis"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

provider "aws" {
  alias = "aws-us-east-1"
  region = "us-east-1"
}

# variable "system" {
#   type = string
#   description = "The two-component shorthand for the platform, e.g x86_64-linux"
#
#   validation  {
#     condition = contains(["x86_64-linux", "aarch64-linux"], var.system)
#     error_message = "System must be one of x86_64-linux or aarch64-linux"
#   }
# }

# variable "ami_path" {
#   type = string
#   description = "Path to the directory containing the VHD file to import"
# }

variable "regions" {
  type = list(string)
  description = "Regions to deploy the AMIs to"
  default = [
    "ap-northeast-1",
    "ap-northeast-2",
    "ap-northeast-3",
    "ap-south-1",
    "ap-southeast-1",
    "ap-southeast-2",
    "ca-central-1",
    "eu-central-1",
    "eu-north-1",
    "eu-west-1",
    "eu-west-2",
    "eu-west-3",
    "sa-east-1",
    "us-east-1",
    "us-east-2",
    "us-west-1",
    "us-west-2"
  ]
}


locals {
  # ami_architecture = (var.system == "aarch64-linux" ? "arm64" : "x86_64")
  providers = { "aws-eu-central-1" = aws, "aws-us-east-1" = aws.aws-us-east-1 }
}

resource "aws_s3_bucket" "cachix-deploy-amis" {
  bucket = "cachix-deploy-amis"
}

resource "aws_s3_bucket_ownership_controls" "cachix-deploy-amis" {
  bucket = aws_s3_bucket.cachix-deploy-amis.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# TODO: is an ACL needed if buckets are private by default?
resource "aws_s3_bucket_acl" "cachix-deploy-amis-acl" {
  depends_on = [ aws_s3_bucket_ownership_controls.cachix-deploy-amis ]

  bucket = aws_s3_bucket.cachix-deploy-amis.id
  acl    = "private"
}

resource "aws_iam_role" "vmimport" {
  name               = "vmimport"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "vmie.amazonaws.com" },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:Externalid": "vmimport"
        }
      }
    }
  ]
}
  EOF
}

resource "aws_iam_role_policy" "vmimport_policy" {
  name   = "vmimport"
  role   = aws_iam_role.vmimport.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:GetBucketLocation",
         "s3:PutObject",
        "s3:GetBucketAcl"
      ],
      "Resource": [
        "${aws_s3_bucket.cachix-deploy-amis.arn}",
        "${aws_s3_bucket.cachix-deploy-amis.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:ModifySnapshotAttribute",
        "ec2:CopySnapshot",
        "ec2:RegisterImage",
        "ec2:Describe*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

# resource "aws_s3_object" "cachix-deploy-vhd" {
#   bucket = aws_s3_bucket.cachix-deploy-amis.bucket
#   key    = local.vhd
#   source = local.vhd
#   source_hash = filemd5(local.vhd)
# }

data "aws_s3_objects" "cachix-deploy-vhds" {
  bucket = aws_s3_bucket.cachix-deploy-amis.bucket
  # prefix = var.ami_path
}

data "aws_s3_object" "cachix-deploy-vhd" {
  for_each = toset(data.aws_s3_objects.cachix-deploy-vhds.keys)

  bucket = aws_s3_bucket.cachix-deploy-amis.bucket
  key = each.value
}

resource "aws_ebs_snapshot_import" "cachix-deploy-snapshot" {
  for_each = data.aws_s3_object.cachix-deploy-vhd

  disk_container {
    format = "VHD"
    user_bucket {
      s3_bucket = aws_s3_bucket.cachix-deploy-amis.bucket
      s3_key    = each.key
    }
  }

  lifecycle {
    create_before_destroy = true
    # replace_triggered_by = [ data.aws_s3_object.cachix-deploy-vhd[each.key].name ]
  }

  role_name = aws_iam_role.vmimport.name
}

resource "aws_ami" "cachix-deploy-ami" {
  for_each            = aws_ebs_snapshot_import.cachix-deploy-snapshot

  name                = "cachix-deploy-ami-${each.value.id}"
  # architecture        = strcontains(each.value.disk_container[0].user_bucket.s3_key, "x86_64-linux") ? "x86_64" : "arm64"
  architecture        = "x86_64"
  virtualization_type = "hvm"
  root_device_name    = "/dev/xvda"
  ena_support         = true
  sriov_net_support   = "simple"

  ebs_block_device {
    device_name           = "/dev/xvda"
    snapshot_id           = each.value.id
    volume_size           = 20
    delete_on_termination = true
    volume_type           = "gp3"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ami_launch_permission" "share-cachix-deploy-ami" {
  for_each = aws_ami.cachix-deploy-ami
  image_id = each.key
  group = "all"
}

module "copy-ami" {
  source = "./modules/copy-ami"

  for_each = local.providers

  aws_provider = each.value
  amis = aws_ami.cachix-deploy.ami
  source_region = "eu-central-1"
}

output "ami-id" {
  value = merge(
    { for k, v in aws_ami.cachix-deploy-ami : k => v.id },
    { for k, v in aws_ami_copy.cachix-deploy-ami : k => v.id }
  )
}
