resource "aws_ami_copy" "cachix-deploy-ami" {
  provider          = var.provider
  name              = var.ami.name
  source_ami_id     = var.ami.id
  source_ami_region = "eu-central-1"

  depends_on = [ aws_ami.cachix-deploy-ami ]
}

