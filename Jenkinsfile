pipeline {
  agent any

  options { timestamps() }

  parameters {
    // Choose how the Jenkins credential `aws-creds` was created:
    // - 'file' : Secret file containing INI-style shared credentials (default)
    // - 'aws'  : AWS Credentials (Access Key / Secret Key / Session Token)
    choice(name: 'CREDENTIALS_KIND', choices: ['file', 'aws'], description: 'Type of Jenkins credentials stored as aws-creds')
    string(name: 'CREDENTIALS_ID', defaultValue: 'aws-creds', description: 'Jenkins Credentials ID')
    string(name: 'AWS_PROFILE_NAME', defaultValue: 'default', description: 'Profile name inside the shared credentials file (if CREDENTIALS_KIND=file)')

    choice(name: 'ACTION', choices: ['plan', 'apply', 'destroy'], description: 'Terraform action')
    booleanParam(name: 'AUTO_APPROVE', defaultValue: false, description: 'Auto-approve apply/destroy')
  }

  environment {
    TF_IN_AUTOMATION = 'true'
    TERRAFORM_DIR    = 'terraform'     // folder that contains your .tf files
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh '''
          set -eux
          echo "PWD:"; pwd
          echo "Top-level listing:"; ls -la
          echo "Listing ${TERRAFORM_DIR}/:"; ls -la "${TERRAFORM_DIR}" || true
          echo "Search for .tf files:"; find . -maxdepth 3 -name "*.tf" -print || true
        '''
      }
    }

    stage('Terraform Init & Validate') {
      steps {
        script {
          if (params.CREDENTIALS_KIND == 'file') {
            // Jenkins Secret file (INI shared-credentials) -> use AWS_SHARED_CREDENTIALS_FILE
            withCredentials([file(credentialsId: params.CREDENTIALS_ID, variable: 'AWS_CREDS_FILE')]) {
              dir(env.TERRAFORM_DIR) {
                withEnv([
                  "AWS_SHARED_CREDENTIALS_FILE=${AWS_CREDS_FILE}",
                  "AWS_PROFILE=${params.AWS_PROFILE_NAME}"
                ]) {
                  sh '''
                    set -eux
                    # Optional visibility (won't fail build if CLI missing)
                    aws --version || true
                    aws sts get-caller-identity || true

                    test -n "$(ls -1 *.tf 2>/dev/null || true)" || { echo "No .tf files in $(pwd)"; exit 1; }

                    terraform fmt -recursive
                    terraform init -input=false
                    terraform validate
                  '''
                }
              }
            }
          } else {
            // Jenkins AWS Credentials (Access/Secret[/Token])
            withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: params.CREDENTIALS_ID]]) {
              dir(env.TERRAFORM_DIR) {
                sh '''
                  set -eux
                  aws --version || true
                  aws sts get-caller-identity || true

                  test -n "$(ls -1 *.tf 2>/dev/null || true)" || { echo "No .tf files in $(pwd)"; exit 1; }

                  terraform fmt -recursive
                  terraform init -input=false
                  terraform validate
                '''
              }
            }
          }
        }
      }
    }

    stage('Terraform Plan / Apply / Destroy') {
      steps {
        script {
          if (params.CREDENTIALS_KIND == 'file') {
            withCredentials([file(credentialsId: params.CREDENTIALS_ID, variable: 'AWS_CREDS_FILE')]) {
              dir(env.TERRAFORM_DIR) {
                withEnv([
                  "AWS_SHARED_CREDENTIALS_FILE=${AWS_CREDS_FILE}",
                  "AWS_PROFILE=${params.AWS_PROFILE_NAME}"
                ]) {
                  if (params.ACTION == 'plan') {
                    sh 'set -eux; terraform plan'
                  } else if (params.ACTION == 'apply') {
                    sh "set -eux; terraform apply ${params.AUTO_APPROVE ? '-auto-approve' : ''}"
                  } else {
                    sh "set -eux; terraform destroy ${params.AUTO_APPROVE ? '-auto-approve' : ''}"
                  }
                }
              }
            }
          } else {
            withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: params.CREDENTIALS_ID]]) {
              dir(env.TERRAFORM_DIR) {
                if (params.ACTION == 'plan') {
                  sh 'set -eux; terraform plan'
                } else if (params.ACTION == 'apply') {
                  sh "set -eux; terraform apply ${params.AUTO_APPROVE ? '-auto-approve' : ''}"
                } else {
                  sh "set -eux; terraform destroy ${params.AUTO_APPROVE ? '-auto-approve' : ''}"
                }
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
    }
  }
}
