pipeline {
    agent any 
    environment {
        SYNC_MAKE_OUTPUT = "none"
        AWS_BUCKET = "jobs.amazeeio.services"
        AWS_DEFAULT_REGION = "us-east-2"
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
                sh 'printenv'
            }
        }

        stage ('download') {
            steps {
                deleteDir()
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
                sh 'docker image prune -af'
            }
        }

        stage('build images') { 
            steps {
                sh 'make -O$SYNC_MAKE_OUTPUT -j8 build'
            }
        }

        stage('show built images') { 
            steps {
                sh 'docker image ls | sort -u'
            }
        }
        
        stage('push branch images to testlagoon/*') { 
            when { 
                not {
                    environment name: 'SKIP_IMAGE_PUBLISH', value: 'true' 
                }
            }
            environment { 
                PASSWORD = credentials('amazeeiojenkins-dockerhub-password') 
            }
            steps {
                sh 'docker login -u amazeeiojenkins -p $PASSWORD'
                sh 'make -O$SYNC_MAKE_OUTPUT -j8 publish-testlagoon-baseimages BRANCH_NAME=$SAFEBRANCH_NAME'
            }
        }



    }
}