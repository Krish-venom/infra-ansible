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
    // Optionally set AWS_DEFAULT_REGION here if needed
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
              set -euo pipefail
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
        withCredentials([usernamePassword(credentialsId: 'aws_creds',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          dir(env.TERRAFORM_DIR) {
            script {
              if (params.ACTION == 'plan') {
                sh '''
                  set -euo pipefail
                  terraform plan -no-color
                '''
              } else if (params.ACTION == 'apply') {
                def approveFlag = params.AUTO_APPROVE ? "-auto-approve" : ""
                sh """
                  set -euo pipefail
                  terraform apply -input=false ${approveFlag} -no-color
                """
              } else {
                def approveFlag = params.AUTO_APPROVE ? "-auto-approve" : ""
                sh """
                  set -euo pipefail
                  terraform destroy -input=false ${approveFlag} -no-color
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
            set -euo pipefail
            terraform output -json > tf_outputs.json
            python3 - <<'PY'
import json, sys
data = json.load(open('tf_outputs.json'))
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
open('ansible_inventory.ini','w').write("\\n".join(lines)+"\\n")
if not apache_ips and not nginx_ips:
  print("No hosts discovered from Terraform outputs; inventory is empty.", file=sys.stderr)
  sys.exit(2)
PY
          '''
        }

        sh '''
          set -euo pipefail
          python3 -m venv "${WORKSPACE}/${VENV}"
          "${WORKSPACE}/${VENV}/bin/pip" install --upgrade pip
          # Pin a major line to avoid breaking changes unexpectedly
          "${WORKSPACE}/${VENV}/bin/pip" install "ansible>=9,<10"
        '''

        script {
          // Read optional PEM path if present, else use Jenkins credential
          def pemPathAbs = ''
          if (fileExists('ANSIBLE_PEM_PATH.txt')) {
            pemPathAbs = readFile(file: 'ANSIBLE_PEM_PATH.txt').trim()
          }

          def ansiblePlaybook  = "${env.WORKSPACE}/${env.VENV}/bin/ansible-playbook"
          def inventoryAbs     = "${env.WORKSPACE}/${env.TERRAFORM_DIR}/ansible_inventory.ini"
          def playbookAbs      = "${env.WORKSPACE}/${env.ANSIBLE_DIR}/${params.ANSIBLE_PLAYBOOK}"

          // Fail early if playbook missing
          if (!fileExists(playbookAbs)) {
            error "Ansible playbook not found at ${playbookAbs}"
          }

          // Execute Ansible
          if (pemPathAbs) {
            sh """
              set -euo pipefail
              "${ansiblePlaybook}" -i "${inventoryAbs}" \\
                --private-key "${pemPathAbs}" \\
                "${playbookAbs}" \\
                -e app_repo_url="${params.APP_REPO_URL}" \\
                -e app_branch="${params.APP_BRANCH}"
            """
          } else {
            withCredentials([sshUserPrivateKey(credentialsId: params.SSH_KEY_CRED_ID,
                                              keyFileVariable: 'SSH_KEY',
                                              usernameVariable: 'SSH_USER')]) {
              sh """
                set -euo pipefail
                "${ansiblePlaybook}" -i "${inventoryAbs}" \\
                  --private-key "${SSH_KEY}" \\
                  "${playbookAbs}" \\
                  -e app_repo_url="${params.APP_REPO_URL}" \\
                  -e app_branch="${params.APP_BRANCH}"
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
