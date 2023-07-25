import click
from functools import cache
import os
import subprocess

@click.group()
def cli():
    pass

@cli.command(help = "Build and release an AMI")
@click.option("--release", default="stable", help="Release to use")
@click.pass_context
def run(ctx, release):
    ami_path = ctx.invoke(build, release=release)
    ctx.invoke(plan, ami_path=ami_path)
    ami_id = ctx.invoke(apply)
    ctx.invoke(multiplex_ami, ami_id=ami_id)

@cli.command(help = "Build an given release AMI (default: stable)")
@click.option("--release", default="stable", help="Release to use")
def build(release):
    ami_path = run_command(f"nix build .#ami-{release} --out-link ami-{release}-{system()} --print-out-paths")
    click.echo(f"\nBuilt: {ami_path}")
    return ami_path

@cli.command(help = "Run Terraform plan")
@click.argument("ami_path")
def plan(ami_path):
    run_command(f"terraform init -input=false -no-color")
    run_command(f"terraform plan -var=ami_path={ami_path} -var=system={system()} -no-color -out=plan.tfplan")

@cli.command(help = "Apply the Terraform created by 'plan'")
def apply():
    run_command(f"terraform apply -input=false -no-color plan.tfplan")
    return run_command(f"terraform output -raw ami-id")

@cli.command(help = "Copy an AMI to all regions")
@click.argument("ami_id")
@click.option("--source-region", default="eu-central-1", help="Source region to copy from")
@click.pass_context
def multiplex_ami(ctx, source_region, ami_id):
    target_regions = ctx.invoke(fetch_regions, source_region=source_region)

    for target_region in target_regions:
        new_ami_json = copy_to_regions(ami_id, source_region, target_regions)
        new_ami = json.loads(new_ami_json)["ImageId"]

def copy_to_region(ami_id, source_region, target_region):
    run_command("aws ec2 copy-image " \
             f"--source-region {source_region} " \
             f"--source-image-id {ami_id} " \
             f"--region {target_region} " \
             "--name cachix-deploy")

@cli.command(help = "Fetch all regions")
@click.option("--source-region", default="eu-central-1", help="Source region to copy from")
def fetch_regions(source_region):
    regions = run_command(f"aws --region {source_region} ec2 describe-regions --query 'Regions[].{{Name:RegionName}}' --output text")
    regions = regions.splitlines()
    click.echo(f"Regions: {regions}")
    return regions

def run_command(command):
    try:
        click.echo(f"Running: {command}")
        with subprocess.Popen(
                  command,
                  shell=True,
                  text=True,
                  stdout=subprocess.PIPE,
                  stderr=subprocess.PIPE,
                  env=os.environ.copy()
                  ) as p:

            for line in p.stderr:
                print(line, end="")

            p.wait()

            if p.returncode != 0:
                raise subprocess.CalledProcessError(p.returncode, p.args)

            return p.stdout.read()

    except subprocess.CalledProcessError as e:
        click.echo(f"Error: Following command exited with code {e.returncode}:\n\n  {e.cmd}", err=True)
        exit(e.returncode)

@cache
def system():
    return run_command("nix eval --raw nixpkgs#system")

@cli.command(help = "Print the Nix system double")
def print_system():
    click.echo(f"{system()}")

