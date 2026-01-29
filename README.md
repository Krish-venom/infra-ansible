
# infra-ansible

Terraform + Ansible + Jenkins pipeline for provisioning and configuring web servers.

## Prereqs

- Jenkins agent with Terraform, Ansible, rsync, Python3
- Jenkins credentials:
  - `aws-credentials-id` (AWS keys)
  - `vm-ssh-key` (private key matching EC2 Key Pair `27-nov`, username `ubuntu`)
- AWS Key Pair exists: **27-nov** (Key Pair name, not .pem)
- Jenkins public IP allowed in SG: **13.201.16.135/32**

## Repos
- Pipeline: https://github.com/Krish-venom/infra-ansible
- Web: https://github.com/Krish-venom/Weather-site

## Run
Create Jenkins pipeline pointing to infra-ansible, run build. Terraform provisions infra and writes `ansible-playbooks/inventory/hosts.ini`. Jenkins checks out Weather-site and runs Ansible to deploy.
