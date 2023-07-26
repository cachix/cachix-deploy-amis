variable "aws_provider" {
  type = object({
    region = string
  })
  description = "Provider configuration"
}

resource "aws_ami_copy" "cachix-deploy-ami" {
  provider          = var.aws_provider
  name              = var.ami.name
  source_ami_id     = var.ami.id
  source_ami_region = "eu-central-1"

  depends_on = [ aws_ami.cachix-deploy-ami ]
}

