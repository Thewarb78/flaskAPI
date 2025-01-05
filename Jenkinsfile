pipeline {
    agent any
    stages {
        stage('Clone Repository') {
            steps {
                git branch: 'main', url: 'http://localhost:7990/scm/fa/flaskapi.git', credentialsId: 'bitbucket-credentials'
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
