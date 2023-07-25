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

variable "system" {
  type = string
  description = "The two-component shorthand for the platform, e.g x86_64-linux"

  validation  {
    condition = contains(["x86_64-linux", "aarch64-linux"], var.system)
    error_message = "System must be one of x86_64-linux or aarch64-linux"
  }
}

variable "ami_path" {
  type = string
  description = "Path to the directory containing the VHD file to import"
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

locals {
  vhd = one(fileset(path.module, "${var.ami_path}/*.vhd"))
  ami_architecture = (var.system == "aarch64-linux" ? "arm64" : "x86_64")
}

resource "aws_s3_object" "cachix-deploy-vhd" {
  bucket = aws_s3_bucket.cachix-deploy-amis.bucket
  key    = local.vhd
  source = local.vhd
  source_hash = filemd5(local.vhd)
}

resource "aws_ebs_snapshot_import" "cachix-deploy-snapshot" {
  disk_container {
    format = "VHD"
    user_bucket {
      s3_bucket = aws_s3_bucket.cachix-deploy-amis.bucket
      s3_key    = aws_s3_object.cachix-deploy-vhd.key
    }
  }

  lifecycle {
    replace_triggered_by = [
      aws_s3_object.cachix-deploy-vhd
    ]
  }

  role_name = aws_iam_role.vmimport.name
}

resource "aws_ami" "cachix-deploy-ami" {
  name                = "cachix-deploy-ami-${aws_ebs_snapshot_import.cachix-deploy-snapshot.id}"
  architecture        = local.ami_architecture
  virtualization_type = "hvm"
  root_device_name    = "/dev/xvda"
  ena_support         = true
  sriov_net_support   = "simple"

  ebs_block_device {
    device_name           = "/dev/xvda"
    snapshot_id           = aws_ebs_snapshot_import.cachix-deploy-snapshot.id
    volume_size           = 20
    delete_on_termination = true
    volume_type           = "gp3"
  }
}

resource "aws_ami_launch_permission" "share-cachix-deploy-ami" {
  image_id = aws_ami.cachix-deploy-ami.id
  group = "all"
}

output "ami-id" {
  value = aws_ami.cachix-deploy-ami.id
}
