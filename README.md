This repository contains a terraform module of AMI ids for NixOS ready to be used with [Cachix Deploy](https://docs.cachix.org/deploy/).

If you're looking to get started using Cachix Deploy with AWS, see the [cachix-deploy-aws](https://github.com/cachix/cachix-deploy-aws) repository.


# Supported versions

- NixOS stable: 22.05
- NixOS unstable

# Terraform module

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_region"></a> [region](#input\_region) | AWS region to use. If not provided, current provider's region will be used. | `string` | `""` | no |
| <a name="input_release"></a> [release](#input\_release) | NixOS version to use: stable or unstable. | `string` | `"stable"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | Cachix Deploy AMI |