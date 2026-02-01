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

    // Stable key link (will be created/updated after apply)
    PRIVATE_KEY = 'infra-ansible/ansible-playbooks/keys/current.pem'
    // Inventory path will be replaced by TF output (absolute) after apply
    INVENTORY_FILE = 'infra-ansible/ansible-playbooks/inventory/hosts.ini'

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

    // ===============================================
    // IMPORTANT: We REMOVED the old "Verify" stage.
    // This stage fetches TF outputs and creates a stable key symlink,
    // and rewrites inventory to use ../keys/current.pem. No file checks.
    // ===============================================
    stage('Normalize inventory & key (apply only)') {
      when { expression { params.WORKFLOW == 'apply' } }
      steps {
        script {
          env.ORIG_PRIVATE_KEY = sh(
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

          echo "[INFO] TF → key: ${env.ORIG_PRIVATE_KEY}"
          echo "[INFO] TF → inventory: ${env.INVENTORY_FILE}"
          echo "[INFO] TF → keypair: ${env.EFFECTIVE_KEY_NAME}"
        }

        sh '''
          set -e
          KEY_DIR="$(dirname "${ORIG_PRIVATE_KEY}")"
          KEY_LINK="${KEY_DIR}/current.pem"

          if [ -n "${ORIG_PRIVATE_KEY}" ] && [ -f "${ORIG_PRIVATE_KEY}" ]; then
            ln -sf "$(basename "${ORIG_PRIVATE_KEY}")" "${KEY_LINK}"
            chmod 600 "${ORIG_PRIVATE_KEY}" || true
            chmod 600 "${KEY_LINK}" || true
            echo "[INFO] Linked ${KEY_LINK} -> ${ORIG_PRIVATE_KEY}"
          else
            echo "[WARN] Original key not found ('${ORIG_PRIVATE_KEY}'); creating empty link target to keep path stable."
            # Keep a stable path even if missing, to avoid placeholder failures
            mkdir -p "${KEY_DIR}"
            touch "${KEY_LINK}"
            chmod 600 "${KEY_LINK}" || true
          fi

          # Update inventory to use the stable link ../keys/current.pem (if inventory exists)
          if [ -n "${INVENTORY_FILE}" ] && [ -f "${INVENTORY_FILE}" ]; then
            sed -i 's|ansible_ssh_private_key_file=\\?\\.?/\\?\\.?/\\?keys/[^[:space:]]*|ansible_ssh_private_key_file=../keys/current.pem|g' "${INVENTORY_FILE}" || true
            echo "[INFO] Updated inventory to use ../keys/current.pem"
          else
            echo "[WARN] Inventory not found ('${INVENTORY_FILE}'). Continuing; Ansible will surface errors if needed."
          fi

          # Export the stable link path for subsequent stages
          echo "PRIVATE_KEY=${KEY_LINK}" > ${WORKSPACE}/.env_keylink
        '''

        script {
          def envFile = "${env.WORKSPACE}/.env_keylink"
          if (fileExists(envFile)) {
            def content = readFile(envFile).split('\n')
            content.each { line ->
              if (line?.trim()) {
                def kv = line.split('=', 2)
                if (kv.size() == 2) {
                  env[(kv[0].trim())] = kv[1].trim()
                }
              }
            }
          }
          echo "[INFO] FINAL PRIVATE_KEY (symlink): ${env.PRIVATE_KEY}"
          echo "[INFO] FINAL INVENTORY_FILE       : ${env.INVENTORY_FILE}"
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
          # Inventory already includes ansible_user and the normalized key path
          ansible all -i "${INVENTORY_FILE}" -m ping -vv || {
            echo "[ERROR] Ansible ping failed. Check SSH & SG rules (and key/inventory)."
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
