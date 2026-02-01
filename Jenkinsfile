pipeline {
  agent any

  options {
    timestamps()
    timeout(time: 20, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '5'))
  }

  parameters {
    choice(name: 'WORKFLOW', choices: ['apply', 'destroy'], description: 'Select terraform workflow')
  }

  environment {
    AWS_DEFAULT_REGION = 'ap-south-1'
    // No trailing slash to avoid var parsing issues in TF
    JENKINS_IP        = 'http://13.201.97.210:8080/'
    TF_DIR            = 'infra-ansible/terraform'
  }

  stages {

    stage('Cleanup Workspace') {
      steps { cleanWs() }
    }

    stage('Checkout Infra Repo') {
      steps {
        dir('infra-ansible') {
          // Remove credentialsId if the repo is public
          git branch: 'main',
              url: 'https://github.com/Krish-venom/infra-ansible.git'
        }
      }
    }

    stage('Terraform Version & Files') {
      steps {
        sh '''
          terraform version || { echo "Terraform not installed on this agent"; exit 1; }
          echo "---- Repo root ----"
          ls -la
          echo "---- Terraform dir ----"
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
              echo "Running terraform init in $(pwd)"
              terraform init -input=false
            '''
          }
        }
      }
    }

    stage('Terraform Validate (optional but recommended)') {
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
                sh """
                  set -e
                  terraform destroy -auto-approve -input=false -var="jenkins_ip=${JENKINS_IP}"
                """
              }
            }
          }
        }
      }
    }

    stage('Terraform Outputs') {
      when { expression { params.WORKFLOW == 'apply' } }
      steps {
        dir("${TF_DIR}") {
          sh 'terraform output || true'
        }
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
