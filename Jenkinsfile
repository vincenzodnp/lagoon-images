pipeline {
    agent any 
    environment {
        SYNC_MAKE_OUTPUT = "none"
    }
    stages {
        stage("Set Env Variables") {
            steps {
                script {
                    env.CI_BUILD_TAG = env.BUILD_TAG.replaceAll('%2f','').replaceAll("[^A-Za-z0-9]+", "").toLowerCase()
                    env.SAFEBRANCH_NAME = env.BRANCH_NAME.replaceAll('%2f','-').replaceAll("[^A-Za-z0-9]+", "-").toLowerCase()
                }
            }
        }

        stage("Show all Variables") {
            steps {
                script {
                    printenv
                }
            }
        }

        stage ('download') {
            steps {
                script {
                    def checkout = checkout scm
                    env.GIT_COMMIT = checkout.GIT_COMMIT
                }
            }
        }

        stage('clean docker image cache') { 
            when {
                buildingTag()
            }
            steps {
                script {
                    docker image prune -af
                }
            }
        }

        stage('build images') { 
            steps {
                sh 'make -O$SYNC_MAKE_OUTPUT -j8 build'
            }
        }

        stage('show built images') { 
            steps {
                script {
                    docker image ls | sort -u
                }
            }
        }

    }
}