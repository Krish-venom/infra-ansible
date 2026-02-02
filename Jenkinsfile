pipeline {
  agent any

  options { timestamps() }

  parameters {
    choice(name: 'ACTION', choices: ['plan', 'apply', 'destroy'], description: 'Terraform action to run')
    booleanParam(name: 'AUTO_APPROVE', defaultValue: true, description: 'Auto-approve apply/destroy (recommended)')
    booleanParam(name: 'RUN_ANSIBLE', defaultValue: false, description: 'Run Ansible after Terraform apply?')
    string(name: 'SSH_KEY_CRED_ID', defaultValue: 'ssh_key', description: 'Fallback Jenkins SSH Private Key Credential ID (used if no PEM was generated)')
    string(name: 'ANSIBLE_PLAYBOOK', defaultValue: 'site.yml', description: 'Playbook to run from ansible-playbooks/ (e.g., site.yml)')
  }

  environment {
    TF_IN_AUTOMATION = 'true'
    TERRAFORM_DIR    = 'terraform'
    ANSIBLE_DIR      = 'ansible-playbooks'
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
        withCredentials([usernamePassword(credentialsId: 'aws_creds', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          dir(env.TERRAFORM_DIR) {
            sh '''
              set -eux
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
                sh 'set -eux; terraform plan -no-color'
              } else if (params.ACTION == 'apply') {
                sh "set -eux; terraform apply -input=false -auto-approve -no-color"
              } else { // destroy
                sh "set -eux; terraform destroy -input=false -auto-approve -no-color"
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
        dir(env.TERRAFORM_DIR) {
          sh '''
            set -eux
            terraform output -json > tf_outputs.json

            # Generate inventory from outputs
            python3 - <<'PY'
import json
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
open('ansible_inventory.ini', 'w').write(inv)
print("Generated inventory:\\n" + inv)
PY

            # Find generated PEM (if any)
            GEN_PEM="$(terraform output -raw generated_private_key_path 2>/dev/null || true)"
            if [ -n "${GEN_PEM}" ] && [ -f "${GEN_PEM}" ]; then
              echo "Using generated PEM: ${GEN_PEM}"
              echo "${GEN_PEM}" > ../ANSIBLE_PEM_PATH.txt
            else
              echo "" > ../ANSIBLE_PEM_PATH.txt
            fi
          '''
        }

        script {
          def pemPath = readFile(file: 'ANSIBLE_PEM_PATH.txt').trim()
          if (pemPath) {
            dir(env.ANSIBLE_DIR) {
              sh """
                set -eux
                ansible --version >/dev/null 2>&1 || { echo "Ansible not found on agent."; exit 1; }
                test -f "../\${TERRAFORM_DIR}/ansible_inventory.ini" || { echo "Inventory not found"; exit 1; }
                ansible-playbook -i "../\${TERRAFORM_DIR}/ansible_inventory.ini" --private-key "${pemPath}" "${params.ANSIBLE_PLAYBOOK}"
              """
            }
          } else {
            withCredentials([sshUserPrivateKey(credentialsId: params.SSH_KEY_CRED_ID, keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')]) {
              dir(env.ANSIBLE_DIR) {
                sh """
                  set -eux
                  ansible --version >/dev/null 2>&1 || { echo "Ansible not found on agent."; exit 1; }
                  test -f "../\${TERRAFORM_DIR}/ansible_inventory.ini" || { echo "Inventory not found"; exit 1; }
                  ansible-playbook -i "../\${TERRAFORM_DIR}/ansible_inventory.ini" --private-key "\${SSH_KEY}" "${params.ANSIBLE_PLAYBOOK}"
                """
              }
            }
          }
        }
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: '**/terraform.tfstate*', allowEmptyArchive: true
      archiveArtifacts artifacts: 'terraform/ansible_inventory.ini', allowEmptyArchive: true
      archiveArtifacts artifacts: 'ANSIBLE_PEM_PATH.txt', allowEmptyArchive: true
    }
  }
}
