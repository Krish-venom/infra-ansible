pipeline {
  agent any
 
  options { timestamps() }
 
  environment {
    AWS_DEFAULT_REGION = 'ap-south-1'
    JENKINS_IP        = 'http://13.201.85.232:8080/'  // Used as a TF var if needed
  }
 
  stages {
 
    stage('Cleanup Workspace') {
      steps { cleanWs() }
    }
 
    stage('Checkout Infra Repo') {
      steps {
        dir('infra-ansible') {
          git branch: 'main',
              url: 'https://github.com/Krish-venom/infra-ansible.git'
        }
      }
    }
 
    stage('Terraform Init') {
      steps {
        dir('infra-ansible/terraform') {
          sh 'terraform init'
        }
      }
    }
 
    stage('Terraform Plan') {
      steps {
        dir('infra-ansible/terraform') {
          sh """
            terraform plan \\
              -var="jenkins_ip=${JENKINS_IP}" \\
              -out=tfplan
          """
        }
      }
    }
 
    // OPTIONAL: keep this if you want a manual gate between plan and apply
    stage('Approval') {
      steps {
        input message: 'Apply the Terraform plan?', ok: 'Apply', submitter: 'admin'
      }
    }
 
    stage('Terraform Apply') {
      steps {
        dir('infra-ansible/terraform') {
          sh 'terraform apply tfplan'
        }
      }
    }
 
    stage('Terraform Outputs') {
      steps {
        dir('infra-ansible/terraform') {
          sh 'terraform output'
        }
      }
    }
  }
 
  post {
    always {
      echo 'Pipeline finished.'
      archiveArtifacts artifacts: 'infra-ansible/terraform/tfplan', onlyIfSuccessful: false
    }
    success { echo '✅ Success!' }
    failure { echo '❌ Build failed. Check logs above.' }
  }
}
 
