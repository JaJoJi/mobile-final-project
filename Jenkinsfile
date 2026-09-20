pipeline {
    agent {
        docker {
            image 'node:20-alpine'
            label 'linux-build'
        }
    }

    environment {
        APP_NAME = 'mobile-final-project'
        NODE_ENV = 'test'
    }

    options {
        // A hung npm install, lint, or test must not hold the Jenkins executor forever.
        timeout(time: 10, unit: 'MINUTES')
    }

    stages {
        stage('Install') {
            steps {
                dir('backend') {
                    sh 'npm ci'
                }
            }
        }

        stage('Lint') {
            steps {
                dir('backend') {
                    sh 'npm run lint'
                }
            }
        }

        stage('Unit Test') {
            steps {
                dir('backend') {
                    sh 'npm test'
                }
            }
        }

        stage('Deploy — Staging') {
        when {
            branch 'jj/dev'
        }
        steps {
            sh 'echo deploying to staging--.'
        }
    }

    stage('Deploy — Production') {
        when {
            branch 'jj/main'
        }
        input {
            message 'Deploy to production?'
        }
        steps {
            sh 'echo deploying to production--.'
        }
    }
    }

    post {
        success {
            echo "SUCCESS: ${env.APP_NAME} passed on ${env.NODE_ENV}"
        }

        failure {
            echo "FAILURE: Failed at stage: ${env.STAGE_NAME}"
        }

        always {
            archiveArtifacts(
                artifacts: 'backend/npm-debug.log*',
                allowEmptyArchive: true
            )
        }
    }
}
