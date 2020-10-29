pipeline {
    agent any 
    environment {
        SYNC_MAKE_OUTPUT = "none"
        AWS_BUCKET = "jobs.amazeeio.services"
        AWS_DEFAULT_REGION = "us-east-2"
        SKIP_IMAGE_PUBLISH = credentials('SKIP_IMAGE_PUBLISH')
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

        stage('set upstream repo and tag for Docker') {
            when {
                beforeInput true
                triggeredBy 'UserIdCause'
            }
            input {
                message "Which Repo and Tag should we pull from?"
                parameters {
                    string(name: 'DOCKER_ORG', defaultValue: "uselagoon", description: 'which Docker org to pull from')
                    string(name: 'DOCKER_TAG', defaultValue: "latest", description: 'which Docker tag to pull')
                }  
            }
            steps {
                script {
                    env.UPSTREAM_REPO = params.DOCKER_ORG
                    env.UPSTREAM_TAG = params.DOCKER_TAG
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

        stage('push tagged images to uselagoon/* and amazeeio/*') { 
            when { 
                buildingTag()
                not {
                    environment name: 'SKIP_IMAGE_PUBLISH', value: 'true' 
                }
            }
            environment { 
                PASSWORD = credentials('amazeeiojenkins-dockerhub-password') 
            }
            steps {
                sh 'docker login -u amazeeiojenkins -p $PASSWORD'
                sh 'make -O$SYNC_MAKE_OUTPUT -j8 publish-uselagoon-baseimages BRANCH_NAME=$SAFEBRANCH_NAME'
                sh 'make -O$SYNC_MAKE_OUTPUT -j8 publish-amazeeio-baseimages BRANCH_NAME=$SAFEBRANCH_NAME'
            }
        }

        stage('push main branch images to s3 and testlagoon/*:latest') { 
            when { 
                buildingTag()
                not {
                    environment name: 'SKIP_IMAGE_PUBLISH', value: 'true' 
                }
            }
            environment { 
                AWS_CREDS = credentials('aws-s3-lagoon') 
            }
            steps {
                script {
                    env.AWS_ACCESS_KEY_ID = AWS_CREDS_USR
                    env.AWS_SECRET_ACCESS_KEY = AWS_CREDS_PSW
                }
                sh 'make -O$SYNC_MAKE_OUTPUT -j8 s3-save'
                sh 'make -O$SYNC_MAKE_OUTPUT -j8 publish-testlagoon-baseimages BRANCH_NAME=latest'
            }
        }


    }
}