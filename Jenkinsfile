pipeline {
  agent any

  options {
    timestamps()
    timeout(time: 45, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '10'))
  }

  parameters {
    choice(name: 'WORKFLOW', choices: ['apply', 'destroy'], description: 'Select Terraform workflow')
    string(name: 'APP_REPO_URL', defaultValue: 'https://github.com/your-org/your-app.git', description: 'Git URL of the application to deploy')
    string(name: 'APP_REPO_BRANCH', defaultValue: 'main', description: 'Branch to deploy')
  }

  environment {
    AWS_DEFAULT_REGION = 'ap-south-1'

    // IMPORTANT: bare IP only (no http://, no port)
    JENKINS_IP = '3.110.120.129'

    // Terraform directory
    TF_DIR = 'infra-ansible/terraform'

    // Placeholder; will be overwritten by TF outputs (absolute paths)
    INVENTORY_FILE = 'infra-ansible/ansible-playbooks/inventory/hosts.ini'
    PRIVATE_KEY    = 'infra-ansible/ansible-playbooks/keys/devops-generated-key-XXXX.pem'

    // App checkout destination
    APP_SRC_DIR = 'app-src'

    // Disable SSH host key checking
    ANSIBLE_HOST_KEY_CHECKING = 'False'
  }

  stages {

    stage('Cleanup Workspace') {
      steps { cleanWs() }
    }

    stage('Checkout Infra Repo') {
      steps {
        dir('infra-ansible') {
          // Add credentialsId if private: credentialsId: 'github_creds'
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
                    -var="jenkins_ip=${JENKINS_IP}"
                """
              }
            }
          }
        }
      }
    }

    // --------- Fetch absolute paths from Terraform outputs (apply only) ---------
    stage('Fetch TF outputs (apply only)') {
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

          echo "[INFO] Using private key: ${env.PRIVATE_KEY}"
          echo "[INFO] Inventory file: ${env.INVENTORY_FILE}"
          echo "[INFO] Effective key pair name: ${env.EFFECTIVE_KEY_NAME}"
        }
      }
    }

    // ----------------- ANSIBLE STAGES (apply only) -----------------
    stage('Verify Inventory & Key (apply only)') {
      when { expression { params.WORKFLOW == 'apply' } }
      steps {
        sh '''
          set -e
          echo "[INFO] Checking inventory & key from Terraform..."
          test -f "${INVENTORY_FILE}" || { echo "Inventory not found: ${INVENTORY_FILE}"; exit 2; }
          test -f "${PRIVATE_KEY}"    || { echo "Private key not found: ${PRIVATE_KEY}"; exit 3; }
          chmod 600 "${PRIVATE_KEY}"
          echo "[INFO] Inventory preview:"
          sed -n '1,200p' "${INVENTORY_FILE}" || true
        '''
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
          # Inventory already carries ansible_user + key path
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

          # Push to Apache servers (Debian/Ubuntu default; fallback for RHEL paths)
          ansible apache -i "${INVENTORY_FILE}" -m unarchive \
            -a "src=${WORKSPACE}/$TAR dest=/var/www/html/ remote_src=no owner=www-data group=www-data mode=0644" -vv || \
          ansible apache -i "${INVENTORY_FILE}" -m unarchive \
            -a "src=${WORKSPACE}/$TAR dest=/usr/share/httpd/noindex/ remote_src=no owner=apache group=apache mode=0644" -vv || true

          # Restart Apache service
          ansible apache -i "${INVENTORY_FILE}" -m service -a "name=apache2 state=restarted" || \
          ansible apache -i "${INVENTORY_FILE}" -m service -a "name=httpd state=restarted" || true

          # Push to Nginx servers (try common roots)
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
