pipeline {
  agent any

  options { timestamps() }

  parameters {
    choice(name: 'ACTION', choices: ['plan', 'apply', 'destroy'], description: 'Terraform action to run')
    booleanParam(name: 'AUTO_APPROVE', defaultValue: false, description: 'Auto-approve apply/destroy')
    booleanParam(name: 'RUN_ANSIBLE', defaultValue: false, description: 'Run Ansible after Terraform apply?')
    string(name: 'SSH_KEY_CRED_ID', defaultValue: 'ssh_key', description: 'Jenkins SSH Private Key Credential ID (used when RUN_ANSIBLE=true)')
    string(name: 'ANSIBLE_PLAYBOOK', defaultValue: 'site.yml', description: 'Playbook to run from ansible-playbooks/ (e.g., site.yml)')
  }

  environment {
    TF_IN_AUTOMATION = 'true'
    TERRAFORM_DIR    = 'terraform'          // your Terraform folder
    ANSIBLE_DIR      = 'ansible-playbooks'  // your Ansible folder
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          set -eux
          echo "PWD:"; pwd
          echo "Top-level listing:"; ls -la
          echo "Listing ${TERRAFORM_DIR}/:"; ls -la "${TERRAFORM_DIR}" || true
          echo "Listing ${ANSIBLE_DIR}/:"; ls -la "${ANSIBLE_DIR}" || true
          echo "Search for .tf files:"; find . -maxdepth 3 -name "*.tf" -print || true
        '''
      }
    }

    stage('Terraform Init & Validate') {
      steps {
        // Use your Jenkins Username/Password credential (ID: aws_creds)
        withCredentials([usernamePassword(credentialsId: 'aws_creds', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          dir(env.TERRAFORM_DIR) {
            sh '''
              set -eux

              # Optional visibility (won't fail if CLI is missing)
              aws --version || true
              aws sts get-caller-identity || true

              # Ensure .tf files are present here
              test -n "$(ls -1 *.tf 2>/dev/null || true)" || { echo "No .tf files in $(pwd)"; exit 1; }

              terraform fmt -recursive
              terraform init -input=false
              terraform validate
            '''
          }
        }
      }
    }

    stage('Terraform Plan / Apply / Destroy') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws_creds', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          dir(env.TERRAFORM_DIR) {
            script {
              if (params.ACTION == 'plan') {
                sh 'set -eux; terraform plan'
              } else if (params.ACTION == 'apply') {
                sh "set -eux; terraform apply ${params.AUTO_APPROVE ? '-auto-approve' : ''}"
              } else { // destroy
                sh "set -eux; terraform destroy ${params.AUTO_APPROVE ? '-auto-approve' : ''}"
              }
            }
          }
        }
      }
    }

    stage('Ansible (optional)') {
      when {
        allOf {
          expression { params.RUN_ANSIBLE == true }
          expression { params.ACTION == 'apply' }
        }
      }
      steps {
        // Requires SSH private key credential to reach the EC2 instances
        withCredentials([sshUserPrivateKey(credentialsId: params.SSH_KEY_CRED_ID, keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')]) {
          dir(env.TERRAFORM_DIR) {
            script {
              // Build Ansible inventory from Terraform outputs using a tiny inline Python (no extra deps).
              // Produces: terraform/ansible_inventory.ini
              sh '''
                set -eux

                # Need Python 3 for JSON parsing. Fail with a friendly hint if not present.
                python3 --version >/dev/null 2>&1 || { echo "Python3 is required to generate inventory. Install python3 or pre-provide an inventory."; exit 1; }

                # Fetch outputs as JSON
                terraform output -json > tf_outputs.json

                # Python: read apache_public_ips & nginx_public_ips, write an INI inventory
                python3 - <<'PY'
import json, os
with open('tf_outputs.json') as f:
    data = json.load(f)
apache_ips = data.get('apache_public_ips', {}).get('value', []) or []
nginx_ips  = data.get('nginx_public_ips', {}).get('value', []) or []
ansible_user = (data.get('ansible_user', {}).get('value', 'ubuntu') if isinstance(data.get('ansible_user', {}), dict) else 'ubuntu')

lines = []
lines.append('[apache]')
for ip in apache_ips:
    lines.append(f'{ip} ansible_user={ansible_user} ansible_ssh_common_args="-o StrictHostKeyChecking=no"')
lines.append('')
lines.append('[nginx]')
for ip in nginx_ips:
    lines.append(f'{ip} ansible_user={ansible_user} ansible_ssh_common_args="-o StrictHostKeyChecking=no"')
inv = "\\n".join(lines).strip() + "\\n"

with open('ansible_inventory.ini', 'w') as f:
    f.write(inv)

print("Generated inventory:\\n" + inv)
PY
              '''
            }
          }

          // Run the requested playbook from ansible-playbooks/ using generated inventory and SSH key
          dir(env.ANSIBLE_DIR) {
            sh '''
              set -eux
              # Ensure Ansible is present
              ansible --version >/dev/null 2>&1 || { echo "Ansible not found. Install Ansible on this agent."; exit 1; }

              # Use the inventory generated by Terraform step
              test -f "../${TERRAFORM_DIR}/ansible_inventory.ini" || { echo "Inventory not found"; exit 1; }

              # Use ubuntu (or ansible_user from inventory), pass private key
              ansible-playbook -i "../${TERRAFORM_DIR}/ansible_inventory.ini" --private-key "$SSH_KEY" "${ANSIBLE_PLAYBOOK}"
            '''
          }
        }
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: '**/terraform.tfstate*', allowEmptyArchive: true
      archiveArtifacts artifacts: 'terraform/ansible_inventory.ini', allowEmptyArchive: true
    }
  }
}
