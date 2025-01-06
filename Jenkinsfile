pipeline {
    agent {
        docker {
            image 'docker:latest'
            args '-v /var/run/docker.sock:/var/run/docker.sock'
        }
    }
    stages {
        stage('Clone Repository') {
            steps {
                git branch: 'master', url: 'http://172.25.96.1:7990/scm/fa/flaskapi.git', credentialsId: '169c2db7-e22d-482a-97d7-a273981b76a6'
            }
        }
        stage('Install Dependencies') {
            steps {
                sh 'pip install -r requirements.txt'
            }
        }
        stage('Build Docker Image') {
            steps {
                sh 'docker build -t flaskapi .'
            }
        }
        stage('Run Tests - change5') {
            steps {
                sh 'pytest tests'
            }
        }
    }
}
