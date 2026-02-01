pipeline {
  agent any

  options {
    timestamps()
    timeout(time: 25, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '10'))
  }

  parameters {
    choice(name: 'WORKFLOW', choices: ['apply', 'destroy'], description: 'Select Terraform workflow')
  }

  environment {
    // Match your Terraform region
    AWS_DEFAULT_REGION = 'ap-south-1'

    // IMPORTANT: bare IP only (no http://, no port, no trailing slash)
    JENKINS_IP = '3.110.120.129'

    // Path where Terraform is located in your repo
    TF_DIR = 'infra-ansible/terraform'

    // This path must match var.public_key_path in Terraform
    PUBKEY_PATH = '/var/lib/jenkins/.ssh/webserver-key.pub'
    PRIVKEY_PATH = '/var/lib/jenkins/.ssh/webserver-key'
  }

  stages {

    stage('Cleanup Workspace') {
      steps {
        cleanWs()
      }
    }

    stage('Checkout Infra Repo') {
      steps {
        dir('infra-ansible') {
          // Add credentialsId if the repo is private: credentialsId: 'github_creds'
          git branch: 'main', url: 'https://github.com/Krish-venom/infra-ansible.git'
        }
      }
    }

    // ✅ Ensure SSH keypair exists on the Jenkins agent BEFORE Terraform runs
    stage('Ensure SSH key exists') {
      steps {
        sh '''
          set -e
          echo "[INFO] Ensuring SSH key exists at ${PUBKEY_PATH}"

          # Create .ssh dir with proper perms
          sudo mkdir -p /var/lib/jenkins/.ssh
          sudo chmod 700 /var/lib/jenkins/.ssh
          sudo chown -R jenkins:jenkins /var/lib/jenkins/.ssh || true

          # Generate keypair if missing
          if [ ! -f "${PUBKEY_PATH}" ] || [ ! -f "${PRIVKEY_PATH}" ]; then
            echo "[INFO] Generating new SSH keypair for Jenkins user..."
            sudo -u jenkins ssh-keygen -t rsa -b 4096 -f "${PRIVKEY_PATH}" -N ""
          else
            echo "[INFO] SSH keypair already exists."
          fi

          # Permissions
          sudo chmod 600 "${PRIVKEY_PATH}"
          sudo chmod 644 "${PUBKEY_PATH}"
          sudo chown -R jenkins:jenkins /var/lib/jenkins/.ssh || true

          # Show brief info (do not print private key)
          echo "[INFO] Key files:"
          ls -l "${PRIVKEY_PATH}" "${PUBKEY_PATH}"
          echo "[INFO] Public key (first 80 chars):"
          head -c 80 "${PUBKEY_PATH}" || true; echo "..."
        '''
      }
    }

    stage('Terraform Version & Layout Check') {
      steps {
        sh '''
          set -e
          echo "Terraform version:"
          terraform version
          echo "---- Repo root ----"
          ls -la
          echo "---- TF_DIR ----"
          ls -la "${TF_DIR}" || true
        '''
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
              echo "Initializing Terraform in $(pwd)"
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
            # Fast backendless init for validate if you want:
            # terraform init -backend=false -input=false
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
            // If you maintain terraform.tfvars, TF will auto-load it.
            // We still pass jenkins_ip explicitly to avoid mistakes.
            sh """
              set -e
              echo "Planning with jenkins_ip=${JENKINS_IP}"
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
        input message: 'Apply the Terraform plan?', ok: 'Apply', submitter: 'admin'
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
                  test -f tfplan || { echo "tfplan not found. Run Plan stage first."; exit 1; }
                  terraform apply -input=false tfplan
                '''
              } else {
                // For destroy, pass the same var explicitly for SG rule.
                sh """
                  set -e
                  echo "Destroying with jenkins_ip=${JENKINS_IP}"
                  terraform destroy -auto-approve -input=false -var="jenkins_ip=${JENKINS_IP}"
                """
              }
            }
          }
        }
      }
    }

    stage('Terraform Outputs (apply only)') {
      when { expression { params.WORKFLOW == 'apply' } }
      steps {
        dir("${TF_DIR}") {
          sh '''
            set +e
            echo "---- Human-readable outputs ----"
            terraform output || true
            echo "---- JSON outputs ----"
            terraform output -json | jq . || true
          '''
        }
      }
    }
  }

  post {
    always {
      echo 'Pipeline finished.'
      archiveArtifacts artifacts: "${TF_DIR}/tfplan", onlyIfSuccessful: false, allowEmptyArchive: true
    }
    success {
      echo '✅ Success!'
    }
    failure {
      echo '❌ Build failed. Check logs above.'
    }
  }
}
