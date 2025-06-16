pipeline {
    agent any

    stages {
        stage('Prepare Deployment Files') {
            steps {
                // Checkout the repository containing docker-compose.yaml and Jenkinsfile
                checkout scm
            }
        }

        stage('Deploy to Production') {
            steps {
                // Use SSH Agent for authentication with production server
                sshagent(credentials: ['jenkins-docker']) {
                    script {
                        def prodUser = 'jay'
                        def prodHost = 'host.docker.internal'
                        def remoteDir = '~/mydata/zentao'

                        // Transfer docker-compose.yaml to production
                        sh """
                          scp -o StrictHostKeyChecking=no docker-compose.yaml ${prodUser}@${prodHost}:${remoteDir}/docker-compose.yaml
                        """

                        // Set permissions for docker-compose.yaml
                        sh """
                          ssh -o StrictHostKeyChecking=no ${prodUser}@${prodHost} \\
                            "cd ${remoteDir} && \\
                             chmod 600 docker-compose.yaml"
                        """

                        // Pull new images and deploy
                        sh """
                          ssh -o StrictHostKeyChecking=no ${prodUser}@${prodHost} \\
                            "cd ${remoteDir} && \\
                             export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && \\
                             docker-compose -f docker-compose.yaml pull && \\
                             docker-compose -f docker-compose.yaml up -d --build --force-recreate --remove-orphans"
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            // Clean up workspace
            cleanWs()
        }
    }
}