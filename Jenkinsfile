
pipeline {
  agent any

  options {
    timestamps()
  }

  parameters {
    string(name: 'INFRA_BRANCH', defaultValue: 'main', description: 'Branch for infra-ansible repo')
    string(name: 'WEB_BRANCH',   defaultValue: 'main', description: 'Branch for Weather-site repo')
    booleanParam(name: 'DESTROY_AFTER', defaultValue: false, description: 'Destroy infra after deploy (lab/testing)')
  }

  environment {
    AWS_DEFAULT_REGION = 'ap-south-1'
    INFRA_REPO_URL = 'https://github.com/Krish-venom/infra-ansible.git'
    WEB_REPO_URL   = 'https://github.com/Krish-venom/Weather-site.git'
  }

  stages {

    stage('Checkout Infra (infra-ansible)') {
      steps {
        checkout([$class: 'GitSCM',
          branches: [[name: "*/${params.INFRA_BRANCH}"]],
          userRemoteConfigs: [[url: env.INFRA_REPO_URL]]
        ])
        sh 'pwd && ls -la'
      }
    }

    stage('Terraform Init & Apply') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'aws-credentials-id',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          dir('terraform') {
            sh '''
              terraform --version || true
              terraform init 
              terraform plan
              terraform apply -auto-approve tfplan
            '''
          }
        }
        sh '''
          echo "==== Generated Ansible Inventory (hosts.ini) ===="
          cat ansible-playbooks/inventory/hosts.ini || true
          echo "==============================================="
        '''
      }
    }

    stage('Checkout Web (Weather-site)') {
      steps {
        dir('web-src') {
          checkout([$class: 'GitSCM',
            branches: [[name: "*/${params.WEB_BRANCH}"]],
            userRemoteConfigs: [[url: env.WEB_REPO_URL]]
          ])
        }
        sh 'ls -la web-src || true'
      }
    }

    stage('Deploy with Ansible') {
      steps {
        sshagent(credentials: ['vm-ssh-key']) {
          dir('ansible-playbooks') {
            withEnv(["WEB_SOURCE_DIR=${env.WORKSPACE}/web-src"]) {
              sh '''
                ansible --version || true
                ansible-playbook -i inventory/hosts.ini -u ubuntu deploy.yml
              '''
            }
          }
        }
      }
    }

    stage('Optional: Terraform Destroy') {
      when { expression { return params.DESTROY_AFTER } }
      steps {
        input message: 'Are you sure you want to destroy the infrastructure?', ok: 'Yes, destroy'
        withCredentials([usernamePassword(credentialsId: 'aws-credentials-id',
                                          usernameVariable: 'AWS_ACCESS_KEY_ID',
                                          passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
          dir('terraform') {
            sh 'terraform destroy -auto-approve'
          }
        }
      }
    }
  }

  post {
    always {
      echo "Pipeline finished."
    }
    failure {
      echo "Build failed. Review logs above."
      archiveArtifacts artifacts: 'ansible-playbooks/inventory/hosts.ini', onlyIfSuccessful: false, allowEmptyArchive: true
    }
    success {
      echo "✅ Deployment successful."
      archiveArtifacts artifacts: 'ansible-playbooks/inventory/hosts.ini', onlyIfSuccessful: true
    }
  }
}
