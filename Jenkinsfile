pipeline {
  agent any

  options { timestamps() }

  parameters {
    string(name: 'TERRAFORM_DIR', defaultValue: '.', description: 'Relative path to folder containing .tf files')
    string(name: 'AWS_REGION', defaultValue: 'ap-south-1', description: 'AWS region')
    string(name: 'ENVIRONMENT', defaultValue: 'production', description: 'Environment')
    string(name: 'PROJECT_NAME', defaultValue: 'devops-webapp', description: 'Project name')
    string(name: 'VPC_ID', defaultValue: 'vpc-0bb695c41dc9db0a4', description: 'Target VPC ID')
    string(name: 'SUBNET_ID', defaultValue: '', description: 'Optional Subnet (empty = auto-pick)')
    booleanParam(name: 'REUSE_EXISTING_SG', defaultValue: true, description: 'Reuse existing SG in VPC?')
    string(name: 'EXISTING_SG_NAME', defaultValue: 'web-server-sg', description: 'Existing SG name when reusing')
    string(name: 'KEYPAIR_NAME', defaultValue: 'deploy-key', description: 'EC2 key pair name')
    string(name: 'ANSIBLE_USER', defaultValue: 'ubuntu', description: 'Ansible SSH user')
    string(name: 'INSTANCE_TYPE', defaultValue: 't3.micro', description: 'EC2 instance type')
    string(name: 'APACHE_INSTANCE_COUNT', defaultValue: '2', description: 'Apache instance count')
    string(name: 'NGINX_INSTANCE_COUNT', defaultValue: '2', description: 'Nginx instance count')
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
        sh """
          set -eux
          echo "Workspace tree (top level):"
          ls -la
          echo "Terraform dir: ${params.TERRAFORM_DIR}"
          ls -la "${params.TERRAFORM_DIR}" || true
        """
      }
    }

    stage('Terraform Init & Validate') {
      steps {
        dir("${params.TERRAFORM_DIR}") {
          sh """
            set -eux
            # Guard: ensure .tf files exist here
            ls -1 *.tf >/dev/null 2>&1

            terraform fmt -recursive
            terraform init -input=false
            terraform validate
          """
        }
      }
    }

    stage('Terraform Plan / Apply / Destroy') {
      steps {
        dir("${params.TERRAFORM_DIR}") {
          script {
            echo "Using VPC_ID: ${params.VPC_ID}"

            // Build -var flags; quote all string values
            def tfVars = """
              -var='aws_region=${params.AWS_REGION}' \
              -var='environment=${params.ENVIRONMENT}' \
              -var='project_name=${params.PROJECT_NAME}' \
              -var='vpc_id=${params.VPC_ID}' \
              -var='subnet_id=${params.SUBNET_ID}' \
              -var='reuse_existing_sg=${params.REUSE_EXISTING_SG}' \
              -var='existing_sg_name=${params.EXISTING_SG_NAME}' \
              -var='keypair_name=${params.KEYPAIR_NAME}' \
              -var='ansible_user=${params.ANSIBLE_USER}' \
              -var='instance_type=${params.INSTANCE_TYPE}' \
              -var='apache_instance_count=${params.APACHE_INSTANCE_COUNT}' \
              -var='nginx_instance_count=${params.NGINX_INSTANCE_COUNT}'
            """.trim()

            if (params.ACTION == 'plan') {
              sh "set -eux; terraform plan ${tfVars}"
            } else if (params.ACTION == 'apply') {
              def approve = params.AUTO_APPROVE ? '-auto-approve' : ''
              sh "set -eux; terraform apply ${approve} ${tfVars}"
            } else { // destroy
              def approve = params.AUTO_APPROVE ? '-auto-approve' : ''
              sh "set -eux; terraform destroy ${approve} ${tfVars}"
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
