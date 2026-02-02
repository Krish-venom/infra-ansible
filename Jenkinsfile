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
    JENKINS_IP = '3.110.85.249'   // bare IP only
    TF_DIR = 'infra-ansible/terraform'
    INVENTORY_FILE = 'infra-ansible/ansible-playbooks/inventory/hosts.ini'
    PRIVATE_KEY    = 'infra-ansible/ansible-playbooks/keys/current.pem'
    APP_SRC_DIR = 'app-src'
    ANSIBLE_HOST_KEY_CHECKING = 'False'
  }

  stages {

    stage('Cleanup Workspace') {
      steps { cleanWs() }
    }

    stage('Checkout Infra Repo') {
      steps {
        dir('infra-ansible') {
          git branch: 'main', url: 'https://github.com/Krish-venom/infra-ansible.git'
        }
      }
    }

    stage('Terraform Init') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws_creds',
          passwordVariable: 'AWS_SECRET_ACCESS_KEY', usernameVariable: 'AWS_ACCESS_KEY_ID')]) {
          dir("${TF_DIR}") {
            sh 'set -e; terraform init -input=false'
          }
        }
      }
    }

    stage('Terraform Validate & Fmt') {
      steps {
        dir("${TF_DIR}") {
          sh 'set -e; terraform fmt -check || true; terraform validate'
        }
      }
    }

    stage('Terraform Plan (apply only)') {
      when { expression { params.WORKFLOW == 'apply' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws_creds',
          passwordVariable: 'AWS_SECRET_ACCESS_KEY', usernameVariable: 'AWS_ACCESS_KEY_ID')]) {
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
          passwordVariable: 'AWS_SECRET_ACCESS_KEY', usernameVariable: 'AWS_ACCESS_KEY_ID')]) {
          dir("${TF_DIR}") {
            script {
              if (params.WORKFLOW == 'apply') {
                sh 'set -e; test -f tfplan || { echo "tfplan not found"; exit 1; }; terraform apply -input=false tfplan'
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

    // Normalize: symlink keys/current.pem -> <fixed> deploy-key.pem & ensure inventory references ../keys/current.pem
    stage('Normalize inventory & key (apply only)') {
      when { expression { params.WORKFLOW == 'apply' } }
      steps {
        script {
          env.PRIVATE_KEY_ABS = sh(
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
          echo "[INFO] key path : ${env.PRIVATE_KEY_ABS}"
          echo "[INFO] inventory: ${env.INVENTORY_FILE}"
          echo "[INFO] keypair  : ${env.EFFECTIVE_KEY_NAME}"
        }

        sh '''
          set -e
          if [ -n "${PRIVATE_KEY_ABS}" ] && [ -f "${PRIVATE_KEY_ABS}" ]; then
            KEY_DIR="$(dirname "${PRIVATE_KEY_ABS}")"
            KEY_LINK="${KEY_DIR}/current.pem"
            ln -sf "$(basename "${PRIVATE_KEY_ABS}")" "${KEY_LINK}"
            chmod 600 "${PRIVATE_KEY_ABS}" || true
            chmod 600 "${KEY_LINK}" || true
            echo "[INFO] Linked ${KEY_LINK} -> ${PRIVATE_KEY_ABS}"
            echo "PRIVATE_KEY=${KEY_LINK}" > ${WORKSPACE}/.env_keylink
          else
            echo "[WARN] Private key path missing or not found ('${PRIVATE_KEY_ABS}'). Creating empty stable link."
            KEY_LINK="infra-ansible/ansible-playbooks/keys/current.pem"
            mkdir -p "$(dirname "${KEY_LINK}")"
            touch "${KEY_LINK}"
            chmod 600 "${KEY_LINK}" || true
            echo "PRIVATE_KEY=${KEY_LINK}" > ${WORKSPACE}/.env_keylink
          fi

          # Ensure inventory points to ../keys/current.pem (it already does from TF, but keep idempotent)
          if [ -n "${INVENTORY_FILE}" ] && [ -f "${INVENTORY_FILE}" ]; then
            sed -i 's|ansible_ssh_private_key_file=\\?\\.?/\\?\\.?/\\?keys/[^[:space:]]*|ansible_ssh_private_key_file=../keys/current.pem|g' "${INVENTORY_FILE}" || true
            echo "[INFO] Inventory updated to use ../keys/current.pem"
          else
            echo "[WARN] Inventory not found ('${INVENTORY_FILE}')."
          fi
        '''

        script {
          def envFile = "${env.WORKSPACE}/.env_keylink"
          if (fileExists(envFile)) {
            readFile(envFile).split('\n').each { line ->
              if (line?.trim()) {
                def kv = line.split('=', 2)
                if (kv.size() == 2) env[(kv[0].trim())] = kv[1].trim()
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
            echo "[WARN] Installing Ansible..."
            if command -v apt-get >/dev/null 2>&1; then
              sudo apt-get update && sudo apt-get install -y ansible
            elif command -v yum >/dev/null 2>&1; then
              sudo yum install -y epel-release || true
              sudo yum install -y ansible || true
            else
              echo "[ERROR] Install Ansible on this agent."
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
            echo "[ERROR] Ansible ping failed. Check SSH/SG rules (and key/inventory)."
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

          # Apache (Ubuntu path then RHEL fallback)
          ansible apache -i "${INVENTORY_FILE}" -m unarchive \
            -a "src=${WORKSPACE}/$TAR dest=/var/www/html/ remote_src=no owner=www-data group=www-data mode=0644" -vv || \
          ansible apache -i "${INVENTORY_FILE}" -m unarchive \
            -a "src=${WORKSPACE}/$TAR dest=/usr/share/httpd/noindex/ remote_src=no owner=apache group=apache mode=0644" -vv || true

          ansible apache -i "${INVENTORY_FILE}" -m service -a "name=apache2 state=restarted" || \
          ansible apache -i "${INVENTORY_FILE}" -m service -a "name=httpd state=restarted" || true

          # Nginx (common roots)
          ansible nginx -i "${INVENTORY_FILE}" -m unarchive \
            -a "src=${WORKSPACE}/$TAR dest=/usr/share/nginx/html/ remote_src=no owner=nginx group=nginx mode=0644" -vv || \
          ansible nginx -i "${INVENTORY_FILE}" -m unarchive \
            -a "src=${WORKSPACE}/$TAR dest=/var/www/html/ remote_src=no owner=www-data group=www-data mode=0644" -vv || true

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
