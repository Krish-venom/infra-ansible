pipeline {
  agent any

  options {
    timestamps()
  }

  // Minimal knobs: you choose what to do; all TF variables come from terraform.tfvars
  parameters {
    choice(name: 'ACTION', choices: ['plan', 'apply', 'destroy'], description: 'Terraform action')
    booleanParam(name: 'AUTO_APPROVE', defaultValue: false, description: 'Auto-approve apply/destroy')
  }

  environment {
    TF_IN_AUTOMATION = 'true'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          set -eux
          echo "PWD:"
          pwd
          echo "Top-level listing:"
          ls -la
          echo "Listing terraform/:"
          ls -la terraform || true
          echo "Search for .tf files:"
          find . -maxdepth 3 -name "*.tf" -print || true
        '''
      }
    }

    stage('Terraform Init & Validate') {
      steps {
        dir('terraform') {
          sh '''
            set -eux
            # Guard: ensure .tf files exist here
            test -n "$(ls -1 *.tf 2>/dev/null || true)" || { echo "No .tf files in $(pwd)"; exit 1; }

            terraform fmt -recursive
            terraform init -input=false
            terraform validate
          '''
        }
      }
    }

    stage('Terraform Plan / Apply / Destroy') {
      steps {
        dir('terraform') {
          script {
            if (params.ACTION == 'plan') {
              sh 'set -eux; terraform plan'
            } else if (params.ACTION == 'apply') {
              def approve = params.AUTO_APPROVE ? '-auto-approve' : ''
              sh "set -eux; terraform apply ${approve}"
            } else { // destroy
              def approve = params.AUTO_APPROVE ? '-auto-approve' : ''
              sh "set -eux; terraform destroy ${approve}"
            }
          }
        }
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: '**/terraform.tfstate*', allowEmptyArchive: true
    }
  }
}
