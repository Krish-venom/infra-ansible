pipeline {
  agent any

  options { timestamps() }

  parameters {
    choice(name: 'ACTION', choices: ['plan', 'apply', 'destroy'], description: 'Terraform action to run')
    booleanParam(name: 'AUTO_APPROVE', defaultValue: true, description: 'Auto-approve apply/destroy (recommended)')
    string(name: 'SSH_KEY_CRED_ID', defaultValue: 'ssh_key', description: 'Fallback Jenkins SSH Private Key Credential ID (used if no PEM was generated)')
    string(name: 'ANSIBLE_PLAYBOOK', defaultValue: 'deploy.yml', description: 'Playbook under ansible-playbooks/ (e.g., deploy.yml or site.yml)')
  }

  environment {
    TF_IN_AUTOMATION = 'true'
    TERRAFORM_DIR    = 'terraform'
    ANSIBLE_DIR      = 'ansible-playbooks'
    ANSIBLE_HOST_KEY_CHECKING = 'False'
    VENV = '.venv-ansible'   // virtualenv directory created in workspace root
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          set -eux
          echo "PWD: $(pwd)"
          echo "Top-level listing:"
          ls -la
          echo "Listing ${TERRAFORM_DIR}/:"
          ls -la "${TERRAFORM_DIR}" || true
          echo "Listing ${ANSIBLE_DIR}/:"
          ls -la "${ANSIBLE_DIR}" || true
          echo "Search for .tf files:"
          find . -maxdepth 3 -name "*.tf" -print || true
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

    // ✅ Ansible is COMPULSORY after apply
    stage('Ansible Configure (mandatory after apply)') {
      when { expression { params.ACTION == 'apply' } }
      steps {
        // 1) Build inventory from Terraform outputs and capture PEM path
        dir(env.TERRAFORM_DIR) {
          sh '''
            set -eux

            # Need Python 3 for inventory generation
            command -v python3 >/dev/null 2>&1 || { echo "python3 not found on agent. Install python3."; exit 1; }
            python3 --version

            terraform output -json > tf_outputs.json

            # Generate inventory from outputs
            python3 - <<'PY'
import json, sys
with open('tf_outputs.json') as f:
    data = json.load(f)
apache_ips = data.get('apache_public_ips', {}).get('value', []) or []
nginx_ips  = data.get('nginx_public_ips', {}).get('value', []) or []
ansible_user = (data.get('ansible_user', {}).get('value', 'ubuntu')
                if isinstance(data.get('ansible_user', {}), dict) else 'ubuntu')

if not apache_ips and not nginx_ips:
    print("ERROR: No instance IPs found in Terraform outputs.", file=sys.stderr)
    sys.exit(1)

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

            # Prefer generated PEM from Terraform if present
            GEN_PEM="$(terraform output -raw generated_private_key_path 2>/dev/null || true)"
            if [ -n "${GEN_PEM}" ] && [ -f "${GEN_PEM}" ]; then
              # Write absolute path to workspace root file
              case "${GEN_PEM}" in
                /*) echo "${GEN_PEM}" > ../ANSIBLE_PEM_PATH.txt ;;
                *)  echo "$(pwd)/${GEN_PEM}" > ../ANSIBLE_PEM_PATH.txt ;;
              esac
            else
              echo "" > ../ANSIBLE_PEM_PATH.txt
            fi

            echo "Inventory: $(pwd)/ansible_inventory.ini"
            echo "PEM path file: $(cd .. && pwd)/ANSIBLE_PEM_PATH.txt"
          '''
        }

        // 2) Create venv in WORKSPACE ROOT and install Ansible (robust: ensurepip + virtualenv fallback)
        sh '''
          set -eux

          echo "Creating/repairing Python venv at: ${WORKSPACE}/${VENV}"

          # 1) Try standard venv if missing
          if [ ! -d "${WORKSPACE}/${VENV}" ]; then
            if python3 -c "import venv" 2>/dev/null; then
              python3 -m venv "${WORKSPACE}/${VENV}" || true
            fi
          fi

          # 2) If still missing, bootstrap ensurepip then retry venv
          if [ ! -d "${WORKSPACE}/${VENV}" ]; then
            python3 -m ensurepip --upgrade || true
            if python3 -c "import venv" 2>/dev/null; then
              python3 -m venv "${WORKSPACE}/${VENV}" || true
            fi
          fi

          # 3) Fallback: use virtualenv in user site
          if [ ! -d "${WORKSPACE}/${VENV}" ]; then
            python3 -m pip install --user --upgrade pip || true
            python3 -m pip install --user virtualenv || true
            USER_BASE="$(python3 -c "import site; print(site.USER_BASE)")"
            USER_BIN="${USER_BASE}/bin"
            if [ -x "${USER_BIN}/virtualenv" ]; then
              "${USER_BIN}/virtualenv" "${WORKSPACE}/${VENV}"
            else
              python3 -m virtualenv "${WORKSPACE}/${VENV}"
            fi
          fi

          # 4) Validate venv and ensure pip inside venv
          if [ ! -x "${WORKSPACE}/${VENV}/bin/python" ]; then
            echo "ERROR: venv Python not found at ${WORKSPACE}/${VENV}/bin/python"
            ls -la "${WORKSPACE}/${VENV}" || true
            exit 1
          fi
          "${WORKSPACE}/${VENV}/bin/python" -m ensurepip --upgrade || true

          # Install Ansible in venv
          "${WORKSPACE}/${VENV}/bin/python" -m pip install --upgrade pip
          "${WORKSPACE}/${VENV}/bin/python" -m pip install --upgrade ansible

          # Verify
          "${WORKSPACE}/${VENV}/bin/ansible" --version

          echo "Venv bin listing:"
          ls -la "${WORKSPACE}/${VENV}/bin"
        '''

        // 3) Run Ansible from TERRAFORM_DIR using ABSOLUTE PATHS for everything
        script {
          def pemPathAbs = readFile(file: 'ANSIBLE_PEM_PATH.txt').trim()
          def ansiblePlaybookBin = "${env.WORKSPACE}/${env.VENV}/bin/ansible-playbook"
          def inventoryAbs       = "${env.WORKSPACE}/${env.TERRAFORM_DIR}/ansible_inventory.ini"
          def playbookAbs        = "${env.WORKSPACE}/${env.ANSIBLE_DIR}/${params.ANSIBLE_PLAYBOOK}"

          dir(env.TERRAFORM_DIR) {
            if (pemPathAbs) {
              sh """
                set -eux
                test -x "${ansiblePlaybookBin}" || { echo "ansible-playbook not found at ${ansiblePlaybookBin}"; exit 1; }
                test -f "${inventoryAbs}" || { echo "Inventory not found at ${inventoryAbs}"; exit 1; }
                test -f "${playbookAbs}" || { echo "Playbook not found at ${playbookAbs}"; exit 1; }
                echo "Running Ansible with generated PEM: ${pemPathAbs}"
                "${ansiblePlaybookBin}" -i "${inventoryAbs}" --private-key "${pemPathAbs}" "${playbookAbs}"
              """
            } else {
              withCredentials([sshUserPrivateKey(credentialsId: params.SSH_KEY_CRED_ID, keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')]) {
                sh """
                  set -eux
                  test -x "${ansiblePlaybookBin}" || { echo "ansible-playbook not found at ${ansiblePlaybookBin}"; exit 1; }
                  test -f "${inventoryAbs}" || { echo "Inventory not found at ${inventoryAbs}"; exit 1; }
                  test -f "${playbookAbs}" || { echo "Playbook not found at ${playbookAbs}"; exit 1; }
                  echo "Running Ansible with Jenkins SSH key credential: \${SSH_KEY}"
                  "${ansiblePlaybookBin}" -i "${inventoryAbs}" --private-key "\${SSH_KEY}" "${playbookAbs}"
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
