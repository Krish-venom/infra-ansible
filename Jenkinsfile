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
    // Region must match your Terraform default or tfvars
    AWS_DEFAULT_REGION = 'ap-south-1'

    // IMPORTANT: bare IP only (no http://, no port, no trailing slash)
    JENKINS_IP = '15.206.72.51'

    // Path where Terraform is located in your repo
    TF_DIR = 'infra-ansible/terraform'
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
          // Add credentialsId if your repo is private, e.g., credentialsId: 'github_creds'
          git branch: 'main', url: 'https://github.com/Krish-venom/infra-ansible.git'
        }
      }
    }

    stage('Terraform Version & Layout Check') {
      steps {
        sh '''
          set -e
          echo "Terraform version:"
          terraform version
          echo "---- Root contents ----"
          ls -la
          echo "---- TF_DIR contents ----"
          ls -la "${TF_DIR}" || true
        '''
      }
    }

    stage('Terraform Init') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws_creds', passwordVariable: 'AWS_SECRET_ACCESS_KEY', usernameVariable: 'AWS_ACCESS_KEY_ID')]) {
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
            terraform fmt -check || true
            terraform validate
          '''
        }
      }
    }

    stage('Terraform Plan (apply only)') {
      when { expression { params.WORKFLOW == 'apply' } }
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws_creds', passwordVariable: 'AWS_SECRET_ACCESS_KEY', usernameVariable: 'AWS_ACCESS_KEY_ID')]) {
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
        withCredentials([usernamePassword(credentialsId: 'aws_creds', passwordVariable: 'AWS_SECRET_ACCESS_KEY', usernameVariable: 'AWS_ACCESS_KEY_ID')]) {
          dir("${TF_DIR}") {
            script {
              if (params.WORKFLOW == 'apply') {
                sh '''
                  set -e
                  test -f tfplan || { echo "tfplan not found. Run Plan stage first."; exit 1; }
                  terraform apply -input=false tfplan
                '''
              } else {
                // For destroy, we pass the same var explicitly to satisfy SG rule build.
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
