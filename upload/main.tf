terraform {
  cloud {
    organization = "cachix"

    workspaces {
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

# The default region
provider "aws" {
  region = "eu-central-1"
}

# AWS providers for each of our enabled regions
provider "aws" {
  alias  = "ap_northeast_1"
  region = "ap-northeast-1"
}

provider "aws" {
  alias  = "ap_northeast_2"
  region = "ap-northeast-2"
}

provider "aws" {
  alias  = "ap_northeast_3"
  region = "ap-northeast-3"
}

provider "aws" {
  alias  = "ap_south_1"
  region = "ap-south-1"
}

provider "aws" {
  alias  = "ap_southeast_1"
  region = "ap-southeast-1"
}

provider "aws" {
  alias  = "ap_southeast_2"
  region = "ap-southeast-2"
}

provider "aws" {
  alias  = "ca_central_1"
  region = "ca-central-1"
}

provider "aws" {
  alias  = "eu_central_1"
  region = "eu-central-1"
}

provider "aws" {
  alias  = "eu_north_1"
  region = "eu-north-1"
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}

provider "aws" {
  alias  = "eu_west_2"
  region = "eu-west-2"
}

provider "aws" {
  alias  = "eu_west_3"
  region = "eu-west-3"
}

provider "aws" {
  alias  = "sa_east_1"
  region = "sa-east-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "us_east_2"
  region = "us-east-2"
}

provider "aws" {
  alias  = "us_west_1"
  region = "us-west-1"
}

provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"
}

# The bucket where we store the original VHDs
# These are uploaded outside of Terraform.
# Once a VHD is deleted, Terraform will destroy the corresponding AMIs.
resource "aws_s3_bucket" "cachix_deploy_amis" {
  bucket = "cachix-deploy-amis"
}

resource "aws_s3_bucket_ownership_controls" "cachix_deploy_amis" {
  bucket = aws_s3_bucket.cachix_deploy_amis.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# TODO: is an ACL needed if buckets are private by default?
resource "aws_s3_bucket_acl" "cachix_deploy_amis_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.cachix_deploy_amis]

  bucket = aws_s3_bucket.cachix_deploy_amis.id
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
        "${aws_s3_bucket.cachix_deploy_amis.arn}",
        "${aws_s3_bucket.cachix_deploy_amis.arn}/*"
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

# List the available VHDs in our bucket
data "aws_s3_objects" "cachix_deploy_vhds" {
  bucket = aws_s3_bucket.cachix_deploy_amis.bucket
}

# Convert each VHD key into an S3 object
data "aws_s3_object" "cachix_deploy_vhd" {
  for_each = toset(data.aws_s3_objects.cachix_deploy_vhds.keys)

  bucket = data.aws_s3_objects.cachix_deploy_vhds.bucket
  key    = each.key
}

# Create an EBS snapshot for each VHD
resource "aws_ebs_snapshot_import" "cachix_deploy_snapshot" {
  for_each = data.aws_s3_object.cachix_deploy_vhd

  disk_container {
    format = "VHD"
    user_bucket {
      s3_bucket = aws_s3_bucket.cachix_deploy_amis.bucket
      s3_key    = each.key
    }
  }

  lifecycle {
    create_before_destroy = true
    # replace_triggered_by = [ data.aws_s3_object.cachix_deploy_vhd[each.key].this ]
  }

  role_name = aws_iam_role.vmimport.name

  tags = {
    Release = each.value.metadata.Release
    System  = each.value.metadata.System
    Arch    = strcontains(each.value.metadata.System, "x86_64-linux") ? "x86_64" : "arm64"
  }
}

# Create an AMI for each EBS snapshot
resource "aws_ami" "cachix_deploy_ami" {
  for_each = aws_ebs_snapshot_import.cachix_deploy_snapshot

  deprecation_time = "2025-08-01T00:00:00Z"

  name                = "cachix_deploy_ami_${each.value.id}"
  architecture        = each.value.tags_all.Arch
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

  tags = {
    Release = each.value.tags_all.Release
    System  = each.value.tags_all.System
    Arch    = each.value.tags_all.Arch
  }
}

# Make the AMIs public
resource "aws_ami_launch_permission" "share_cachix_deploy_ami" {
  for_each = aws_ami.cachix_deploy_ami
  image_id = each.value.id
  group    = "all"
}

# Begin copying the original AMI to every enabled region.
module "copy_ami_ap_northeast_1" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.ap_northeast_1 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

module "copy_ami_ap_northeast_2" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.ap_northeast_2 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

module "copy_ami_ap_northeast_3" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.ap_northeast_3 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

module "copy_ami_ap_south_1" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.ap_south_1 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

module "copy_ami_ap_southeast_1" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.ap_southeast_1 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

module "copy_ami_ap_southeast_2" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.ap_southeast_2 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

module "copy_ami_ca_central_1" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.ca_central_1 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

module "copy_ami_eu_north_1" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.eu_north_1 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

module "copy_ami_eu_west_1" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.eu_west_1 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

module "copy_ami_eu_west_2" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.eu_west_2 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

module "copy_ami_eu_west_3" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.eu_west_3 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

module "copy_ami_sa_east_1" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.sa_east_1 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

module "copy_ami_us_east_1" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.us_east_1 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

module "copy_ami_us_east_2" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.us_east_2 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

module "copy_ami_us_west_1" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.us_west_1 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

module "copy_ami_us_west_2" {
  source        = "./modules/copy_ami"
  for_each      = aws_ami.cachix_deploy_ami
  providers     = { aws = aws.us_west_2 }
  ami           = each.value
  source_region = "eu-central-1"
  depends_on    = [aws_ami.cachix_deploy_ami]
}

# TODO: this can be made simpler by extracting the ami stuff into a separate module.
# We then use for_each on that module and flatten just once.
# That and maybe switch to lists instead of maps at some point in the for_each waterfall.
locals {
  source_ami = {
    for v in values(aws_ami.cachix_deploy_ami) :
    "${v.tags_all.Release}.eu-central-1.${v.tags_all.System}" => v.id
  }

  regional_amis = [
    module.copy_ami_ap_northeast_1,
    module.copy_ami_ap_northeast_2,
    module.copy_ami_ap_northeast_3,
    module.copy_ami_ap_south_1,
    module.copy_ami_ap_southeast_1,
    module.copy_ami_ap_southeast_2,
    module.copy_ami_ca_central_1,
    module.copy_ami_eu_north_1,
    module.copy_ami_eu_west_1,
    module.copy_ami_eu_west_2,
    module.copy_ami_eu_west_3,
    module.copy_ami_sa_east_1,
    module.copy_ami_us_east_1,
    module.copy_ami_us_east_2,
    module.copy_ami_us_west_1,
    module.copy_ami_us_west_2
  ]

  regional_ami_ids = merge(flatten([
    for m in local.regional_amis : [
      for a in values(m) : [a.ami]
    ]
  ])...)
}

output "ami_ids" {
  value = merge(
    local.source_ami,
    local.regional_ami_ids
  )
}
