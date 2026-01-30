pipeline {
  agent any
 
  options {
    timestamps()
  }
 
  environment {
    AWS_DEFAULT_REGION = 'ap-south-1'
    JENKINS_IP        = 'http://13.233.224.234:8080/'
    ANSIBLE_HOST_KEY_CHECKING = 'False'
  }
 
  stages {
 
    stage('Cleanup Workspace') {
      steps { cleanWs() }
    }
 
    stage('Checkout Repositories') {
      parallel {
        stage('Checkout Infra (terraform + ansible)') {
          steps {
            dir('infra-ansible') {
              git branch: 'main',
                  url: 'https://github.com/Krish-venom/infra-ansible.git'
            }
          }
        }
        stage('Checkout Web (Weather-site)') {
          steps {
            dir('webapp') {
              git branch: 'main',
                  url: 'https://github.com/Krish-venom/Weather-site.git'
            }
          }
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
 
    stage('Terraform Validate') {
      steps {
        dir('infra-ansible/terraform') {
          sh 'terraform validate'
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
 
    stage('Approval') {
      steps {
        input message: 'Proceed to deploy 4 EC2 instances (2 Apache + 2 Nginx)?',
              ok: 'Deploy',
              submitter: 'admin'
      }
    }
 
    stage('Terraform Apply') {
      steps {
        dir('infra-ansible/terraform') {
          sh 'terraform apply tfplan'
        }
      }
    }
 
    stage('Wait for EC2 to be reachable') {
      steps { sleep(time: 90, unit: 'SECONDS') }
    }
 
    stage('Generate Ansible Inventory (from Terraform outputs)') {
      steps {
        dir('infra-ansible/terraform') {
          sh 'terraform output -json > ../ansible-playbooks/inventory/tf-outputs.json'
        }
        script {
          def tfJson  = readFile("infra-ansible/ansible-playbooks/inventory/tf-outputs.json")
          def slurper = new groovy.json.JsonSlurperClassic()
          def obj     = slurper.parseText(tfJson)
 
          def apacheIps = obj.apache_public_ips?.value ?: []
          def nginxIps  = obj.nginx_public_ips?.value  ?: []
 
          def ini = new StringBuilder()
          ini.append("[apache]\n")
          apacheIps.each { ip -> ini.append("${ip} ansible_user=ec2-user\n") }
          ini.append("\n[nginx]\n")
          nginxIps.each { ip -> ini.append("${ip} ansible_user=ec2-user\n") }
          ini.append("\n[all:vars]\n")
          ini.append("ansible_python_interpreter=/usr/bin/python3\n")
 
          writeFile file: "infra-ansible/ansible-playbooks/inventory/hosts.ini", text: ini.toString()
        }
        dir('infra-ansible/ansible-playbooks') {
          sh 'echo "===== Generated hosts.ini ====="; cat inventory/hosts.ini'
        }
      }
    }
 
    stage('Test SSH Connectivity') {
      steps {
        // Uses Jenkins credential ID: webserver-deploy-key (SSH Username with private key; username ec2-user)
        sshagent(credentials: ['webserver-deploy-key']) {
          dir('infra-ansible/ansible-playbooks') {
            sh '''
              export ANSIBLE_HOST_KEY_CHECKING=${ANSIBLE_HOST_KEY_CHECKING}
              ansible -i inventory/hosts.ini all -m ping
            '''
          }
        }
      }
    }
 
    stage('Deploy with Ansible') {
      steps {
        sshagent(credentials: ['webserver-deploy-key']) {
          dir('infra-ansible/ansible-playbooks') {
            sh '''
              export ANSIBLE_HOST_KEY_CHECKING=${ANSIBLE_HOST_KEY_CHECKING}
              # Pass webapp dir so playbook can copy index.html
              ansible-playbook -i inventory/hosts.ini deploy.yml -e "webapp_dir=${WORKSPACE}/webapp"
            '''
          }
        }
      }
    }
 
    stage('Deployment Info') {
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
      archiveArtifacts artifacts: 'infra-ansible/ansible-playbooks/inventory/hosts.ini, infra-ansible/terraform/*.tf, infra-ansible/terraform/tfplan', onlyIfSuccessful: false
    }
    success { echo '✅ Success!' }
    failure { echo '❌ Build failed. Check logs above.' }
  }
}
