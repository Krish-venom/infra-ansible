pipeline {
  agent any

  options { timestamps() }

  parameters {
    choice(name: 'ACTION', choices: ['plan', 'apply', 'destroy'], description: 'Terraform action to run')
    booleanParam(name: 'AUTO_APPROVE', defaultValue: true, description: 'Auto-approve apply/destroy')

    // Application repo defaults
    string(name: 'APP_REPO_URL', defaultValue: 'https://github.com/Krish-venom/Weather-site.git', description: 'Git URL of the app to deploy')
    string(name: 'APP_BRANCH',   defaultValue: 'main', description: 'Branch to deploy')

    // SSH key fallback
    string(name: 'SSH_KEY_CRED_ID', defaultValue: 'ssh_key', description: 'Jenkins SSH Private Key credential ID')
    string(name: 'ANSIBLE_PLAYBOOK', defaultValue: 'deploy.yml', description: 'Playbook under ansible-playbooks/ to run')
  }

  environment {
    TF_IN_AUTOMATION = 'true'
    TERRAFORM_DIR    = 'terraform'
    ANSIBLE_DIR      = 'ansible-playbooks'
    ANSIBLE_HOST_KEY_CHECKING = 'False'
    VENV     = '.venv-ansible'
    // If your provider blocks don't set region, uncomment and set the region:
    // AWS_DEFAULT_REGION = 'ap-south-1'
  }

  stages {
    stage('Checkout Infra Repo') {
      steps {
        checkout scm
      }
    }

    stage('Terraform Init & Validate') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws_creds',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          dir(env.TERRAFORM_DIR) {
            sh '''
bash -Eeuo pipefail <<'EOF'
terraform fmt -recursive
terraform init -input=false
terraform validate
EOF
'''
          }
        }
      }
    }

    stage('Terraform Plan / Apply / Destroy') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws_creds',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          dir(env.TERRAFORM_DIR) {
            script {
              if (params.ACTION == 'plan') {
                sh '''
bash -Eeuo pipefail <<'EOF'
terraform plan -no-color
EOF
'''
              } else if (params.ACTION == 'apply') {
                def approveFlag = params.AUTO_APPROVE ? "-auto-approve" : ""
                sh """bash -Eeuo pipefail <<'EOF'
terraform apply -input=false ${approveFlag} -no-color
EOF
"""
              } else {
                def approveFlag = params.AUTO_APPROVE ? "-auto-approve" : ""
                sh """bash -Eeuo pipefail <<'EOF'
terraform destroy -input=false ${approveFlag} -no-color
EOF
"""
              }
            }
          }
        }
      }
    }

    stage('Ansible Configure + Deploy') {
      when { expression { params.ACTION == 'apply' } }
      steps {
        dir(env.TERRAFORM_DIR) {
          sh '''
bash -Eeuo pipefail <<'EOF'
terraform output -json > tf_outputs.json

python3 - <<'PY'
import json, sys
with open('tf_outputs.json') as f:
    data = json.load(f)

apache_ips = data.get('apache_public_ips', {}).get('value', []) or []
nginx_ips  = data.get('nginx_public_ips', {}).get('value', []) or []
ansible_user = data.get('ansible_user', {}).get('value', 'ubuntu')

lines = []
if apache_ips:
    lines.append('[apache]')
    for ip in apache_ips:
        lines.append(f"{ip} ansible_user={ansible_user} ansible_ssh_common_args=-o StrictHostKeyChecking=no")
if nginx_ips:
    lines.append('[nginx]')
    for ip in nginx_ips:
        lines.append(f"{ip} ansible_user={ansible_user} ansible_ssh_common_args=-o StrictHostKeyChecking=no")

with open('ansible_inventory.ini','w') as f:
    f.write("\\n".join(lines) + "\\n")

if not apache_ips and not nginx_ips:
    print("No hosts discovered from Terraform outputs; inventory is empty.", file=sys.stderr)
    sys.exit(2)
PY
EOF
'''
        }

        // Create venv and install Ansible (version pinned)
        sh '''
bash -Eeuo pipefail <<'EOF'
python3 -m venv "${WORKSPACE}/${VENV}"
"${WORKSPACE}/${VENV}/bin/pip" install --upgrade pip
# Pin major line to avoid sudden breaking changes
"${WORKSPACE}/${VENV}/bin/pip" install "ansible>=9,<10"
EOF
'''

        script {
          // Read optional PEM path if present (in workspace root), else use Jenkins credential
          def pemPathAbs = ''
          if (fileExists('ANSIBLE_PEM_PATH.txt')) {
            pemPathAbs = readFile(file: 'ANSIBLE_PEM_PATH.txt').trim()
          }

          def ansiblePlaybook  = "${env.WORKSPACE}/${env.VENV}/bin/ansible-playbook"
          def inventoryAbs     = "${env.WORKSPACE}/${env.TERRAFORM_DIR}/ansible_inventory.ini"
          def playbookAbs      = "${env.WORKSPACE}/${env.ANSIBLE_DIR}/${params.ANSIBLE_PLAYBOOK}"

          if (!fileExists(playbookAbs)) {
            error "Ansible playbook not found at ${playbookAbs}"
          }

          if (pemPathAbs) {
            sh """bash -Eeuo pipefail <<'EOF'
"${ansiblePlaybook}" -i "${inventoryAbs}" \\
  --private-key "${pemPathAbs}" \\
  "${playbookAbs}" \\
  -e app_repo_url="${params.APP_REPO_URL}" \\
  -e app_branch="${params.APP_BRANCH}"
EOF
"""
          } else {
            withCredentials([sshUserPrivateKey(credentialsId: params.SSH_KEY_CRED_ID,
                                              keyFileVariable: 'SSH_KEY',
                                              usernameVariable: 'SSH_USER')]) {
              sh """bash -Eeuo pipefail <<'EOF'
"${ansiblePlaybook}" -i "${inventoryAbs}" \\
  --private-key "${SSH_KEY}" \\
  "${playbookAbs}" \\
  -e app_repo_url="${params.APP_REPO_URL}" \\
  -e app_branch="${params.APP_BRANCH}"
EOF
"""
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
    }
  }
}
