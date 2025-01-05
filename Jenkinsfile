pipeline {
    agent any
    stages {
        stage('Clone Repository') {
            steps {
                git branch: 'main', url: 'ssh://git@localhost:7999/fa/flaskapi.git', credentialsId: 'bitbucket-ssh'
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
        stage('Run Tests') {
            steps {
                sh 'pytest tests'
            }
        }
    }
}
