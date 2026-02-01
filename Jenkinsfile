pipeline {
  agent any

  options {
    timestamps()
    timeout(time: 45, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '10'))
  }

  parameters {
    choice(name: 'WORKFLOW', choices: ['apply', 'destroy'], description: 'Select Terraform workflow')
    string(name: 'VPC_ID', defaultValue: 'vpc-0bb695c41dc9db0a4', description: 'Existing VPC ID to deploy into (default VPC)')
    string(name: 'SUBNET_ID', defaultValue: '', description: 'Optional: specific subnet in the VPC (leave empty to auto-pick first)')
    string(name: 'APP_REPO_URL', defaultValue: 'https://github.com/your-org/your-app.git', description: 'Git URL of the application to deploy')
    string(name: 'APP_REPO_BRANCH', defaultValue: 'main', description: 'Branch to deploy')
  }

  environment {
    AWS_DEFAULT_REGION = 'ap-south-1'
    // IMPORTANT: bare IP only (no http://, no port)
    JENKINS_IP = '3.110.120.129'

    // Terraform directory in your repo
    TF_DIR = 'infra-ansible/terraform'

    // These will be overwritten after apply by TF outputs (absolute paths)
    INVENTORY_FILE = 'infra-ansible/ansible-playbooks/inventory/hosts.ini'
    PRIVATE_KEY    = 'infra-ansible/ansible-playbooks/keys/devops-generated-key-PLACEHOLDER.pem'

    // App checkout destination
    APP_SRC_DIR = 'app-src'

    // Disable SSH host key prompts during first connect
    ANSIBLE_HOST_KEY_CHECKING = 'False'
  }

  stages {

    stage('Cleanup Workspace') {
      steps { cleanWs() }
    }

    stage('Checkout Infra Repo') {
      steps {
        dir('infra-ansible') {
          // If private, add: credentialsId: 'github_creds'
          git branch: 'main', url: 'https://github.com/Krish-venom/infra-ansible.git'
        }
      }
    }

    stage('Terraform Init') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws_creds',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID')]) {
          dir("${TF_DIR}") {
            sh '''
              set -e
              terraform init -input=false
            '''
          }
        }
      }
    }

    stage('Terraform Validate & Fmt') {
      steps {
        dir("${TF_DIR}") {
          sh '''
            set -e
            terraform fmt -check || true
            terraform validate
          '''
        }
      }
    }

    stage('Terraform Plan (apply only)') {
      when { expression { params.WORKFLOW == 'apply' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws_creds',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID')]) {
          dir("${TF_DIR}") {
            sh """
              set -e
              terraform plan \\
                -input=false \\
                -var="jenkins_ip=${JENKINS_IP}" \\
                -var="vpc_id=${VPC_ID}" \\
                -var="subnet_id=${SUBNET_ID}" \\
                -out=tfplan
            """
          }
        }
      }
    }

    stage('Approval (apply only)') {
      when { expression { params.WORKFLOW == 'apply' } }
      steps {
        input message: 'Apply the Terraform plan and proceed to Ansible deploy?', ok: 'Apply', submitter: 'admin'
      }
    }

    stage('Terraform Apply / Destroy') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws_creds',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID')]) {
          dir("${TF_DIR}") {
            script {
              if (params.WORKFLOW == 'apply') {
                sh '''
                  set -e
                  test -f tfplan || { echo "tfplan not found. Run Plan first."; exit 1; }
                  terraform apply -input=false tfplan
                '''
              } else {
                sh """
                  set -e
                  terraform destroy -auto-approve -input=false \\
                    -var="jenkins_ip=${JENKINS_IP}" \\
                    -var="vpc_id=${VPC_ID}" \\
                    -var="subnet_id=${SUBNET_ID}"
                """
              }
            }
          }
        }
      }
    }

    stage('Auto-fix inventory & key paths (apply only)') {
      when { expression { params.WORKFLOW == 'apply' } }
      steps {
        script {
          env.PRIVATE_KEY = sh(
            script: "terraform -chdir=${TF_DIR} output -raw generated_private_key_path",
            returnStdout: true
          ).trim()

          env.INVENTORY_FILE = sh(
            script: "terraform -chdir=${TF_DIR} output -raw inventory_path",
            returnStdout: true
          ).trim()

          env.EFFECTIVE_KEY_NAME = sh(
            script: "terraform -chdir=${TF_DIR} output -raw effective_keypair_name",
            returnStdout: true
          ).trim()

          echo "[INFO] TF outputs → key: ${env.PRIVATE_KEY}"
          echo "[INFO] TF outputs → inventory: ${env.INVENTORY_FILE}"
          echo "[INFO] TF outputs → keypair: ${env.EFFECTIVE_KEY_NAME}"
        }

        sh '''
          set -e
          echo "[INFO] Auto-fix: checking inventory & key files..."

          # --- Normalize INVENTORY_FILE ---
          if [ ! -f "${INVENTORY_FILE}" ]; then
            echo "[WARN] Inventory not found at ${INVENTORY_FILE}, attempting auto-fix..."
            CAND1="${TF_DIR}/../ansible-playbooks/inventory/hosts.ini"
            CAND2="infra-ansible/ansible-playbooks/inventory/hosts.ini"
            if [ -f "${CAND1}" ]; then
              INVENTORY_FILE="$(cd "$(dirname "${CAND1}")" && pwd)/$(basename "${CAND1}")"
              echo "[INFO] Found inventory at ${INVENTORY_FILE}"
            elif [ -f "${CAND2}" ]; then
              INVENTORY_FILE="$(cd "$(dirname "${CAND2}")" && pwd)/$(basename "${CAND2}")"
              echo "[INFO] Found inventory at ${INVENTORY_FILE}"
            else
              echo "[WARN] Could not locate inventory file automatically. Proceeding; Ansible may fail if inventory is wrong."
            fi
          fi

          # --- Normalize PRIVATE_KEY ---
          if [ ! -f "${PRIVATE_KEY}" ]; then
            echo "[WARN] Private key not found at ${PRIVATE_KEY}, attempting auto-fix..."
            KEY_BASENAME="${EFFECTIVE_KEY_NAME}.pem"
            CANDK1="${TF_DIR}/../ansible-playbooks/keys/${KEY_BASENAME}"
            CANDK2="infra-ansible/ansible-playbooks/keys/${KEY_BASENAME}"
            CANDK3="ansible-playbooks/keys/${KEY_BASENAME}"

            if [ -f "${CANDK1}" ]; then
              PRIVATE_KEY="$(cd "$(dirname "${CANDK1}")" && pwd)/$(basename "${CANDK1}")"
              echo "[INFO] Found key at ${PRIVATE_KEY}"
            elif [ -f "${CANDK2}" ]; then
              PRIVATE_KEY="$(cd "$(dirname "${CANDK2}")" && pwd)/$(basename "${CANDK2}")"
              echo "[INFO] Found key at ${PRIVATE_KEY}"
            elif [ -f "${CANDK3}" ]; then
              PRIVATE_KEY="$(cd "$(dirname "${CANDK3}")" && pwd)/$(basename "${CANDK3}")"
              echo "[INFO] Found key at ${PRIVATE_KEY}"
            else
              echo "[WARN] Could not locate private key automatically. Proceeding; Ansible may fail if key is missing."
            fi
          fi

          # Fix permissions if key exists now
          if [ -f "${PRIVATE_KEY}" ]; then
            chmod 600 "${PRIVATE_KEY}" || true
          fi

          echo "[INFO] Using inventory: ${INVENTORY_FILE}"
          echo "[INFO] Using private key: ${PRIVATE_KEY}"
          echo "[INFO] Inventory preview (if present):"
          sed -n '1,200p' "${INVENTORY_FILE}" 2>/dev/null || true

          {
            echo "INVENTORY_FILE=${INVENTORY_FILE}"
            echo "PRIVATE_KEY=${PRIVATE_KEY}"
          } >> ${WORKSPACE}/.env_autofix
        '''
        script {
          def envFile = "${env.WORKSPACE}/.env_autofix"
          if (fileExists(envFile)) {
            def content = readFile(envFile).split('\n')
            content.each { line ->
              if (line?.trim()) {
                def kv = line.split('=', 2)
                if (kv.size() == 2) {
                  def k = kv[0].trim()
                  def v = kv[1].trim()
                  if (k && v) {
                    env[k] = v
                  }
                }
              }
            }
          }
          echo "[INFO] Final INVENTORY_FILE: ${env.INVENTORY_FILE}"
          echo "[INFO] Final PRIVATE_KEY   : ${env.PRIVATE_KEY}"
        }
      }
    }

    stage('Prepare Ansible (apply only)') {
      when { expression { params.WORKFLOW == 'apply' } }
      steps {
        sh '''
          set +e
          if ! command -v ansible >/dev/null 2>&1; then
            echo "[WARN] Ansible not found. Installing..."
            if command -v apt-get >/dev/null 2>&1; then
              sudo apt-get update && sudo apt-get install -y ansible
            elif command -v yum >/dev/null 2>&1; then
              sudo yum install -y epel-release || true
              sudo yum install -y ansible || true
            else
              echo "[ERROR] Could not install Ansible automatically. Please install Ansible on the Jenkins agent."
              exit 1
            fi
          fi
          ansible --version
        '''
      }
    }

    stage('Fetch Application Code (apply only)') {
      when { expression { params.WORKFLOW == 'apply' } }
      steps {
        dir("${APP_SRC_DIR}") {
          // Add credentialsId if app repo is private
          checkout([$class: 'GitSCM',
            branches: [[name: params.APP_REPO_BRANCH]],
            userRemoteConfigs: [[url: params.APP_REPO_URL]]
          ])
        }
      }
    }

    stage('Ansible Ping (apply only)') {
      when { expression { params.WORKFLOW == 'apply' } }
      steps {
        sh '''
          set -e
          ansible all -i "${INVENTORY_FILE}" -m ping -vv || {
            echo "[ERROR] Ansible ping failed. Check SSH & SG rules."
            exit 1
          }
        '''
      }
    }

    stage('Package & Push App (apply only)') {
      when { expression { params.WORKFLOW == 'apply' } }
      steps {
        sh '''
          set -e
          TAR="app.tgz"
          rm -f "$TAR"
          tar -C "${APP_SRC_DIR}" -czf "$TAR" .

          # Push to Apache servers (Debian/Ubuntu default; fallback for RHEL path)
          ansible apache -i "${INVENTORY_FILE}" -m unarchive \
            -a "src=${WORKSPACE}/$TAR dest=/var/www/html/ remote_src=no owner=www-data group=www-data mode=0644" -vv || \
          ansible apache -i "${INVENTORY_FILE}" -m unarchive \
            -a "src=${WORKSPACE}/$TAR dest=/usr/share/httpd/noindex/ remote_src=no owner=apache group=apache mode=0644" -vv || true

          # Restart Apache
          ansible apache -i "${INVENTORY_FILE}" -m service -a "name=apache2 state=restarted" || \
          ansible apache -i "${INVENTORY_FILE}" -m service -a "name=httpd state=restarted" || true

          # Push to Nginx servers (common roots)
          ansible nginx -i "${INVENTORY_FILE}" -m unarchive \
            -a "src=${WORKSPACE}/$TAR dest=/usr/share/nginx/html/ remote_src=no owner=nginx group=nginx mode=0644" -vv || \
          ansible nginx -i "${INVENTORY_FILE}" -m unarchive \
            -a "src=${WORKSPACE}/$TAR dest=/var/www/html/ remote_src=no owner=www-data group=www-data mode=0644" -vv || true

          # Restart Nginx
          ansible nginx -i "${INVENTORY_FILE}" -m service -a "name=nginx state=restarted" || true
        '''
      }
    }
  }

  post {
    always {
      echo 'Pipeline finished.'
      archiveArtifacts artifacts: "${TF_DIR}/tfplan", onlyIfSuccessful: false, allowEmptyArchive: true
    }
    success { echo '✅ Success!' }
    failure { echo '❌ Build failed. Check logs above.' }
  }
}
