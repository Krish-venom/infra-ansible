pipeline {
  agent any
 
  options {
    timestamps()
    ansiColor('xterm')
  }
 
  environment {
    AWS_DEFAULT_REGION = 'ap-south-1'
    JENKINS_IP        = 'http://13.233.224.234:8080/'
    WEBAPP_DIR        = "${WORKSPACE}/webapp"
    TERRAFORM_DIR     = "${WORKSPACE}/terraform"
    ANSIBLE_DIR       = "${WORKSPACE}/ansible-playbooks"
    // Optional: disable Ansible host key checking
    ANSIBLE_HOST_KEY_CHECKING = 'False'
  }
 
  stages {
 
    stage('Cleanup Workspace') {
      steps { cleanWs() }
    }
 
    stage('Checkout Repositories') {
      parallel {
        stage('Webapp') {
          steps {
            dir('webapp') {
              // If repo is public, you can remove credentialsId
              git branch: 'main',
                  credentialsId: 'gitSCM',
                  url: 'https://github.com/Krish-venom/Weather-site.git'
            }
          }
        }
        stage('Infra (Terraform + Ansible)') {
          steps {
            dir('infra-ansible') {
              git branch: 'main',
                  credentialsId: 'gitSCM',
                  url: 'https://github.com/Krish-venom/infra-ansible.git'
            }
          }
        }
      }
    }
 
    stage('Prepare Folders') {
      steps {
        sh '''
          ln -sfn ${WORKSPACE}/infra-ansible/terraform ${WORKSPACE}/terraform
          ln -sfn ${WORKSPACE}/infra-ansible/ansible-playbooks ${WORKSPACE}/ansible-playbooks
        '''
      }
    }
 
    stage('Terraform Init') {
      steps {
        dir('terraform') {
          sh 'terraform init'
        }
      }
    }
 
    stage('Terraform Validate') {
      steps {
        dir('terraform') {
          sh 'terraform validate'
        }
      }
    }
 
    stage('Terraform Plan') {
      steps {
        dir('terraform') {
          sh '''
            terraform plan \
              -var="jenkins_ip=${JENKINS_IP}" \
              -out=tfplan
          '''
        }
      }
    }
 
    stage('Approval') {
      steps {
        input message: 'Deploy 4 EC2 instances (2 Apache + 2 Nginx)?',
              ok: 'Deploy',
              submitter: 'admin'
      }
    }
 
    stage('Terraform Apply') {
      steps {
        dir('terraform') {
          // Using the saved plan; no additional -auto-approve required
          sh 'terraform apply tfplan'
        }
      }
    }
 
    stage('Wait for EC2 to be reachable') {
      steps { sleep(time: 90, unit: 'SECONDS') }
    }
 
    stage('Generate Ansible Inventory (from Terraform outputs)') {
      steps {
        dir('terraform') {
          sh 'terraform output -json > ../ansible-playbooks/inventory/tf-outputs.json'
        }
        script {
          // Parse JSON and create hosts.ini using Groovy (no extra plugins needed)
          def jsonText = readFile("${ANSIBLE_DIR}/inventory/tf-outputs.json")
          def slurper  = new groovy.json.JsonSlurperClassic()
          def obj      = slurper.parseText(jsonText)
 
          // Terraform outputs: apache_public_ips & nginx_public_ips must exist
          def apacheIps = obj.apache_public_ips?.value ?: []
          def nginxIps  = obj.nginx_public_ips?.value  ?: []
 
          // Build INI content
          def ini = new StringBuilder()
          ini.append("[apache]\n")
          apacheIps.each { ip -> ini.append("${ip} ansible_user=ec2-user\n") }
          ini.append("\n[nginx]\n")
          nginxIps.each { ip -> ini.append("${ip} ansible_user=ec2-user\n") }
          ini.append("\n[all:vars]\n")
          ini.append("ansible_python_interpreter=/usr/bin/python3\n")
          // You can omit the next line because we use sshagent
          // ini.append("ansible_ssh_private_key_file=~/.ssh/webserver-deploy-key\n")
 
          writeFile file: "${ANSIBLE_DIR}/inventory/hosts.ini", text: ini.toString()
        }
        // Show inventory for debugging
        dir('ansible-playbooks') {
          sh 'echo "===== Generated hosts.ini ====="; cat inventory/hosts.ini'
        }
      }
    }
 
    stage('Test SSH Connectivity') {
      steps {
        sshagent(credentials: ['webserver-deploy-key']) {
          dir('ansible-playbooks') {
            sh '''
              export ANSIBLE_HOST_KEY_CHECKING=${ANSIBLE_HOST_KEY_CHECKING}
              ansible -i inventory/hosts.ini all -m ping
            '''
          }
        }
      }
    }
 
    stage('Deploy Application') {
      steps {
        sshagent(credentials: ['webserver-deploy-key']) {
          dir('ansible-playbooks') {
            sh '''
              export ANSIBLE_HOST_KEY_CHECKING=${ANSIBLE_HOST_KEY_CHECKING}
              ansible-playbook -i inventory/hosts.ini deploy.yml
            '''
          }
        }
      }
    }
 
    stage('Deployment Info') {
      steps {
        dir('terraform') {
          sh '''
            echo "===== Terraform Outputs ====="
            terraform output
          '''
        }
      }
    }
  }
 
  post {
    success { echo '✅ PIPELINE COMPLETED SUCCESSFULLY' }
    failure { echo '❌ PIPELINE FAILED' }
  }
}
