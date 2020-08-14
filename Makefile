SHELL := /bin/bash
# amazee.io lagoon Makefile The main purpose of this Makefile is to provide easier handling of
# building images and running tests It understands the relation of the different images (like
# nginx-drupal is based on nginx) and builds them in the correct order Also it knows which
# services in docker-compose.yml are depending on which base images or maybe even other service
# images
#
# The main commands are:

# make build/<imagename>
# Builds an individual image and all of it's needed parents. Run `make build-list` to get a list of
# all buildable images. Make will keep track of each build image with creating an empty file with
# the name of the image in the folder `build`. If you want to force a rebuild of the image, either
# remove that file or run `make clean`

# make build
# builds all images in the correct order. Uses existing images for layer caching, define via `TAG`
# which branch should be used

# make tests/<testname>
# Runs individual tests. In a nutshell it does:
# 1. Builds all needed images for the test
# 2. Starts needed Lagoon services for the test via docker-compose up
# 3. Executes the test
#
# Run `make tests-list` to see a list of all tests.

# make tests
# Runs all tests together. Can be executed with `-j2` for two parallel running tests

# make up
# Starts all Lagoon Services at once, usefull for local development or just to start all of them.

# make logs
# Shows logs of Lagoon Services (aka docker-compose logs -f)

#######
####### Default Variables
#######

# Parameter for all `docker build` commands, can be overwritten by passing `DOCKER_BUILD_PARAMS=` via the `-e` option
DOCKER_BUILD_PARAMS := --quiet

# On CI systems like jenkins we need a way to run multiple testings at the same time. We expect the
# CI systems to define an Environment variable CI_BUILD_TAG which uniquely identifies each build.
# If it's not set we assume that we are running local and just call it lagoon.
CI_BUILD_TAG ?= lagoon
BASE_IMAGE_REPO ?= lagoon
BASE_IMAGE_TAG ?= master
CORE_IMAGE_REPO ?= amazeeiolagoon
CORE_IMAGE_TAG ?= v1-8-2

# Local environment
ARCH := $(shell uname | tr '[:upper:]' '[:lower:]')
LAGOON_VERSION := $(shell git describe --tags --exact-match 2>/dev/null || echo development)
LAGOON_TAG := $(shell git describe --tags --exact-match 2>/dev/null)
DOCKER_DRIVER := $(shell docker info -f '{{.Driver}}')

# Version and Hash of the k8s tools that should be downloaded
K3S_VERSION := v1.17.9-k3s1
KUBECTL_VERSION := v1.17.9
HELM_VERSION := v3.2.4
K3D_VERSION := 1.7.0

# k3d has a 35-char name limit
K3D_NAME := k3s-$(shell echo $(CI_BUILD_TAG) | sed -E 's/.*(.{31})$$/\1/')

# Name of the Branch we are currently in
BRANCH_NAME :=
DEFAULT_ALPINE_VERSION := 3.11


# Init the file that is used to hold the image tag cross-reference table
$(file >build.txt)

#######
####### Functions
#######

# Builds a docker image. Expects as arguments: name of the image, location of Dockerfile, path of
# Docker Build Context
docker_build = docker build $(DOCKER_BUILD_PARAMS) --build-arg LAGOON_VERSION=$(LAGOON_VERSION) --build-arg IMAGE_REPO=$(CI_BUILD_TAG) --build-arg ALPINE_VERSION=$(DEFAULT_ALPINE_VERSION) -t $(CI_BUILD_TAG)/$(1) -f $(2) $(3)

# Tags an image with the `amazeeio` repository and pushes it
docker_publish_amazeeio = docker tag $(CI_BUILD_TAG)/$(1) amazeeio/$(2) && docker push amazeeio/$(2) | cat

# Tags an image with the `amazeeiolagoon` repository and pushes it
docker_publish_amazeeiolagoon = docker tag $(CI_BUILD_TAG)/$(1) amazeeiolagoon/$(2) && docker push amazeeiolagoon/$(2) | cat

#######
####### Base Images
#######
####### Base Images are the base for all other images and are also published for clients to use during local development

deploy-images := kubectl-build-deploy-dind \
							docker-host

consumer-images :=     commons \
							mariadb \
							mariadb-drupal \
							mongo \
							nginx \
							nginx-drupal \
							varnish \
							varnish-drupal \
							varnish-persistent \
							varnish-persistent-drupal \
							athenapdf-service \
							toolbox

# base-images is a variable that will be constantly filled with all base image there are
base-images += $(consumer-images)
s3-images += $(consumer-images)

# List with all images prefixed with `build/`. Which are the commands to actually build images
build-images = $(foreach image,$(consumer-images),build/$(image))

# Define the make recipe for all base images
$(build-images):
#	Generate variable image without the prefix `build/`
	$(eval image = $(subst build/,,$@))
# Call the docker build
	$(call docker_build,$(image),images/$(image)/Dockerfile,images/$(image))
# Populate the cross-reference table
	$(file >>build.txt,$(CI_BUILD_TAG)/$(image) $(CI_BUILD_TAG)/$(image) amazeeio/$(image)$(if $(LAGOON_TAG),:$(LAGOON_TAG)) amazeeiolagoon/$(image)$(if $(BRANCH_NAME),:$(BRANCH_NAME)))
# Touch an empty file which make itself is using to understand when the image has been last build
	touch $@

# Define dependencies of Base Images so that make can build them in the right order. There are two
# types of Dependencies
# 1. Parent Images, like `build/centos7-node6` is based on `build/centos7` and need to be rebuild
#    if the parent has been built
# 2. Dockerfiles of the Images itself, will cause make to rebuild the images if something has
#    changed on the Dockerfiles
build/commons: images/commons/Dockerfile
build/mariadb: build/commons images/mariadb/Dockerfile
build/mariadb-drupal: build/mariadb images/mariadb-drupal/Dockerfile
build/mongo: build/commons images/mongo/Dockerfile
build/nginx: build/commons images/nginx/Dockerfile
build/nginx-drupal: build/nginx images/nginx-drupal/Dockerfile
build/varnish: build/commons images/varnish/Dockerfile
build/varnish-drupal: build/varnish images/varnish-drupal/Dockerfile
build/varnish-persistent: build/varnish images/varnish/Dockerfile
build/varnish-persistent-drupal: build/varnish-persistent images/varnish-drupal/Dockerfile
build/docker-host: build/commons images/docker-host/Dockerfile
build/athenapdf-service: build/commons images/athenapdf-service/Dockerfile
build/toolbox: build/commons build/mariadb images/toolbox/Dockerfile
build/kubectl-build-deploy-dind: build/kubectl images/kubectl-build-deploy-dind

#######
####### Multi-version Images
#######

multiimages := 	php-7.2-fpm \
				php-7.3-fpm \
				php-7.4-fpm \
				php-7.2-cli \
				php-7.3-cli \
				php-7.4-cli \
				php-7.2-cli-drupal \
				php-7.3-cli-drupal \
				php-7.4-cli-drupal \
				python-2.7 \
				python-3.7 \
				python-3.8 \
				python-3.9.0rc1 \
				python-2.7-ckan \
				python-2.7-ckandatapusher \
				node-10 \
				node-12 \
				node-14 \
				node-10-builder \
				node-12-builder \
				node-14-builder \
				solr-5.5 \
				solr-6.6 \
				solr-7.7 \
				solr-5.5-drupal \
				solr-6.6-drupal \
				solr-7.7-drupal \
				solr-5.5-ckan \
				solr-6.6-ckan \
				elasticsearch-6 \
				elasticsearch-7 \
				kibana-6 \
				kibana-7 \
				logstash-6 \
				logstash-7 \
				postgres-11 \
				postgres-12 \
				postgres-11-ckan \
				postgres-11-drupal \
				redis-5 \
				redis-6 \
				redis-5-persistent \
				redis-6-persistent

build-multiimages = $(foreach image,$(multiimages),build/$(image))

# Define the make recipe for all multi images
$(build-multiimages):
	$(eval image = $(subst build/,,$@))
	$(eval variant = $(word 1,$(subst -, ,$(image))))
	$(eval version = $(word 2,$(subst -, ,$(image))))
	$(eval type = $(word 3,$(subst -, ,$(image))))
	$(eval subtype = $(word 4,$(subst -, ,$(image))))
# Construct the folder and legacy tag to use - note that if treats undefined vars as 'false' to avoid extra '-/'
	$(eval folder = $(shell echo $(variant)$(if $(type),/$(type))$(if $(subtype),/$(subtype))))
	$(eval legacytag = $(shell echo $(variant)$(if $(version),:$(version))$(if $(type),-$(type))$(if $(subtype),-$(subtype))))
# Call the generic docker build process
	$(call docker_build,$(image),images/$(folder)/$(if $(version),$(version).)Dockerfile,images/$(folder))
# Populate the cross-reference table
	$(file >>build.txt,$(CI_BUILD_TAG)/$(image) $(CI_BUILD_TAG)/$(legacytag) amazeeio/$(legacytag)$(if $(LAGOON_TAG),-$(LAGOON_TAG)) amazeeiolagoon/$(legacytag)$(if $(BRANCH_NAME),-$(BRANCH_NAME)))
# Touch an empty file which make itself is using to understand when the image has been last built
	touch $@

base-images-with-versions += $(multiimages)
s3-images += $(multiimages)

build/php-7.2-fpm build/php-7.3-fpm build/php-7.4-fpm: build/commons
build/php-7.2-cli: build/php-7.2-fpm
build/php-7.3-cli: build/php-7.3-fpm
build/php-7.4-cli: build/php-7.4-fpm
build/php-7.2-cli-drupal: build/php-7.2-cli
build/php-7.3-cli-drupal: build/php-7.3-cli
build/php-7.4-cli-drupal: build/php-7.4-cli
build/python-2.7 build/python-3.7 build/python-3.8 build/python-3.9.0rc1: build/commons
build/python-2.7-ckan: build/python-2.7
build/python-2.7-ckandatapusher: build/python-2.7
build/node-10 build/node-12 build/node-14: build/commons
build/node-10-builder: build/node-10
build/node-12-builder: build/node-12
build/node-14-builder: build/node-14
build/solr-5.5  build/solr-6.6 build/solr-7.7: build/commons
build/solr-5.5-drupal: build/solr-5.5
build/solr-6.6-drupal: build/solr-6.6
build/solr-7.7-drupal: build/solr-7.7
build/solr-5.5-ckan: build/solr-5.5
build/solr-6.6-ckan: build/solr-6.6
build/elasticsearch-6 build/elasticsearch-7 build/kibana-6 build/kibana-7 build/logstash-6 build/logstash-7: build/commons
build/postgres-11 build/postgres-12: build/commons
build/postgres-11-ckan build/postgres-11-drupal: build/postgres-11
build/redis-5 build/redis-6: build/commons
build/redis-5-persistent: build/redis-5
build/redis-5 build/redis-6: build/commons
build/redis-6-persistent: build/redis-6

# Images for local helpers that exist in another folder than the service images
localdevimages := local-git \
									local-api-data-watcher-pusher \
									local-registry\
									local-dbaas-provider
build-localdevimages = $(foreach image,$(localdevimages),build/$(image))

$(build-localdevimages):
	$(eval folder = $(subst build/local-,,$@))
	$(eval image = $(subst build/,,$@))
	$(call docker_build,$(image),$(image),local-dev/$(folder)/Dockerfile,local-dev/$(folder))
	touch $@

# Image with ansible test
build/tests:
	$(eval image = $(subst build/,,$@))
	$(call docker_build,$(image),$(image),$(image)/Dockerfile,$(image))
	touch $@

#######
####### Commands
#######
####### List of commands in our Makefile

# Builds all Images
.PHONY: build
build: $(foreach image,$(base-images) $(base-images-with-versions) ,build/$(image))

# Outputs a list of all Images we manage
.PHONY: build-list
build-list:
	@for number in $(foreach image,$(base-images) $(base-images-with-versions),build/$(image)); do \
			echo $$number ; \
	done

# Define list of all tests
all-k8s-tests-list:= features-kubernetes \
									nginx \
									drupal \
									active-standby-kubernetes
all-k8s-tests = $(foreach image,$(all-k8s-tests-list),k8s-tests/$(image))

# Run all k8s tests
.PHONY: k8s-tests
k8s-tests: $(all-k8s-tests)

.PHONY: $(all-k8s-tests)
$(all-k8s-tests): k3d pull up
		$(MAKE) push-local-registry -j6
		$(eval testname = $(subst k8s-tests/,,$@))
		IMAGE_REPO=$(CORE_IMAGE_REPO) IMAGE_TAG=$(CORE_IMAGE_TAG) docker-compose -p $(CI_BUILD_TAG) --compatibility run --rm \
			tests-kubernetes ansible-playbook --skip-tags="skip-on-kubernetes" \
			/ansible/tests/$(testname).yaml \
			--extra-vars \
			"$$(cat $$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)') | \
				jq -rcsR '{kubeconfig: .}')"

# push command of our base images
push-local-registry-images = $(foreach image,$(base-images) $(base-images-with-versions),[push-local-registry]-$(image))
# tag and push all images
.PHONY: push-local-registry
push-local-registry: $(push-local-registry-images)
# tag and push of each image
.PHONY:
	docker login -u admin -p admin 172.17.0.1:8084
	$(push-local-registry-images)

$(push-local-registry-images):
	$(eval image = $(subst [push-local-registry]-,,$@))
	$(eval image = $(subst __,:,$(image)))
	$(info pushing $(image) to local local-registry)
	if docker inspect $(BASE_IMAGE_REPO)/$(image) > /dev/null 2>&1; then \
		docker tag $(BASE_IMAGE_REPO)/$(image) localhost:5000/lagoon/$(image) && \
		docker push localhost:5000/lagoon/$(image) | cat; \
	fi

# Run all tests
.PHONY: tests
tests: k8s-tests

# Wait for Keycloak to be ready (before this no API calls will work)
.PHONY: wait-for-keycloak
wait-for-keycloak:
	$(info Waiting for Keycloak to be ready....)
	grep -m 1 "Config of Keycloak done." <(docker-compose -p $(CI_BUILD_TAG) --compatibility logs -f keycloak 2>&1)

.PHONY: local-registry-up
local-registry-up: build/local-registry
	IMAGE_REPO=$(CORE_IMAGE_REPO) IMAGE_TAG=$(CORE_IMAGE_TAG) docker-compose -p $(CI_BUILD_TAG) --compatibility up -d local-registry

# Publish command to amazeeio docker hub, this should probably only be done during a master deployments
publish-amazeeio-baseimages = $(foreach image,$(base-images),[publish-amazeeio-baseimages]-$(image))
publish-amazeeio-baseimages-with-versions = $(foreach image,$(base-images-with-versions),[publish-amazeeio-baseimages-with-versions]-$(image))
# tag and push all images
.PHONY: publish-amazeeio-baseimages
publish-amazeeio-baseimages: $(publish-amazeeio-baseimages) $(publish-amazeeio-baseimages-with-versions)


# tag and push of each image
.PHONY: $(publish-amazeeio-baseimages)
$(publish-amazeeio-baseimages):
#   Calling docker_publish for image, but remove the prefix '[publish-amazeeio-baseimages]-' first
		$(eval image = $(subst [publish-amazeeio-baseimages]-,,$@))
# 	Publish images as :latest
		$(call docker_publish_amazeeio,$(image),$(image):latest)
# 	Publish images with version tag
		$(call docker_publish_amazeeio,$(image),$(image):$(LAGOON_VERSION))


# tag and push of base image with version
.PHONY: $(publish-amazeeio-baseimages-with-versions)
$(publish-amazeeio-baseimages-with-versions):
#   Calling docker_publish for image, but remove the prefix '[publish-amazeeio-baseimages-with-versions]-' first
		$(eval image = $(subst [publish-amazeeio-baseimages-with-versions]-,,$@))
#   The underline is a placeholder for a colon, replace that
		$(eval image = $(subst __,:,$(image)))
#		These images already use a tag to differentiate between different versions of the service itself (like node:9 and node:10)
#		We push a version without the `-latest` suffix
		$(call docker_publish_amazeeio,$(image),$(image))
#		Plus a version with the `-latest` suffix, this makes it easier for people with automated testing
		$(call docker_publish_amazeeio,$(image),$(image)-latest)
#		We add the Lagoon Version just as a dash
		$(call docker_publish_amazeeio,$(image),$(image)-$(LAGOON_VERSION))



# Publish command to amazeeio docker hub, this should probably only be done during a master deployments
publish-amazeeiolagoon-baseimages = $(foreach image,$(base-images),[publish-amazeeiolagoon-baseimages]-$(image))
publish-amazeeiolagoon-baseimages-with-versions = $(foreach image,$(base-images-with-versions),[publish-amazeeiolagoon-baseimages-with-versions]-$(image))
# tag and push all images
.PHONY: publish-amazeeiolagoon-baseimages
publish-amazeeiolagoon-baseimages: $(publish-amazeeiolagoon-baseimages) $(publish-amazeeiolagoon-baseimages-with-versions)


# tag and push of each image
.PHONY: $(publish-amazeeiolagoon-baseimages)
$(publish-amazeeiolagoon-baseimages):
#   Calling docker_publish for image, but remove the prefix '[publish-amazeeiolagoon-baseimages]-' first
		$(eval image = $(subst [publish-amazeeiolagoon-baseimages]-,,$@))
# 	Publish images with version tag
		$(call docker_publish_amazeeiolagoon,$(image),$(image):$(BRANCH_NAME))


# tag and push of base image with version
.PHONY: $(publish-amazeeiolagoon-baseimages-with-versions)
$(publish-amazeeiolagoon-baseimages-with-versions):
#   Calling docker_publish for image, but remove the prefix '[publish-amazeeiolagoon-baseimages-with-versions]-' first
		$(eval image = $(subst [publish-amazeeiolagoon-baseimages-with-versions]-,,$@))
#   The underline is a placeholder for a colon, replace that
		$(eval image = $(subst __,:,$(image)))
#		We add the Lagoon Version just as a dash
		$(call docker_publish_amazeeiolagoon,$(image),$(image)-$(BRANCH_NAME))

s3-save = $(foreach image,$(s3-images),[s3-save]-$(image))
# save all images to s3
.PHONY: s3-save
s3-save: $(s3-save)
# tag and push of each image
.PHONY: $(s3-save)
$(s3-save):
#   remove the prefix '[s3-save]-' first
		$(eval image = $(subst [s3-save]-,,$@))
		$(eval image = $(subst __,:,$(image)))
		docker save $(CI_BUILD_TAG)/$(image) $$(docker history -q $(CI_BUILD_TAG)/$(image) | grep -v missing) | gzip -9 | aws s3 cp - s3://lagoon-images/$(image).tar.gz

s3-load = $(foreach image,$(s3-images),[s3-load]-$(image))
# save all images to s3
.PHONY: s3-load
s3-load: $(s3-load)
# tag and push of each image
.PHONY: $(s3-load)
$(s3-load):
#   remove the prefix '[s3-load]-' first
		$(eval image = $(subst [s3-load]-,,$@))
		$(eval image = $(subst __,:,$(image)))
		curl -s https://s3.us-east-2.amazonaws.com/lagoon-images/$(image).tar.gz | gunzip -c | docker load

# Clean all build touches, which will case make to rebuild the Docker Images (Layer caching is
# still active, so this is a very safe command)
clean:
	rm -rf build/*

# Show Lagoon Service Logs
logs:
	IMAGE_REPO=$(CI_BUILD_TAG) docker-compose -p $(CI_BUILD_TAG) --compatibility logs --tail=10 -f $(service)

# Pre-pull all images for docker-compose
pull:
	IMAGE_REPO=$(CORE_IMAGE_REPO) IMAGE_TAG=$(CORE_IMAGE_TAG) docker-compose -p $(CI_BUILD_TAG) pull --include-deps --quiet

# Start all Lagoon Services
up:
ifeq ($(ARCH), darwin)
	IMAGE_REPO=$(CORE_IMAGE_REPO) IMAGE_TAG=$(CORE_IMAGE_TAG) docker-compose -p $(CI_BUILD_TAG) --compatibility up -d
else
	# once this docker issue is fixed we may be able to do away with this
	# linux-specific workaround: https://github.com/docker/cli/issues/2290
	KEYCLOAK_URL=$$(docker network inspect -f '{{(index .IPAM.Config 0).Gateway}}' bridge):8088 \
		IMAGE_REPO=$(CORE_IMAGE_REPO) IMAGE_TAG=$(CORE_IMAGE_TAG) \
		docker-compose -p $(CI_BUILD_TAG) --compatibility up -d
endif
	grep -m 1 ".opendistro_security index does not exist yet" <(docker-compose -p $(CI_BUILD_TAG) logs -f logs-db 2>&1)
	while ! docker exec "$$(docker-compose -p $(CI_BUILD_TAG) ps -q logs-db)" ./securityadmin_demo.sh; do sleep 5; done
	$(MAKE) wait-for-keycloak

down:
	IMAGE_REPO=$(CORE_IMAGE_REPO) IMAGE_TAG=$(CORE_IMAGE_TAG) docker-compose -p $(CI_BUILD_TAG) --compatibility down -v --remove-orphans

# kill all containers containing the name "lagoon"
kill:
	docker ps --format "{{.Names}}" | grep lagoon | xargs -t -r -n1 docker rm -f -v

# Symlink the installed k3d client if the correct version is already
# installed, otherwise downloads it.
local-dev/k3d:
ifeq ($(K3D_VERSION), $(shell k3d version 2>/dev/null | grep k3d | sed -E 's/^k3d version v([0-9.]+).*/\1/'))
	$(info linking local k3d version $(K3D_VERSION))
	ln -s $(shell command -v k3d) ./local-dev/k3d
else
	$(info downloading k3d version $(K3D_VERSION) for $(ARCH))
	curl -Lo local-dev/k3d https://github.com/rancher/k3d/releases/download/v$(K3D_VERSION)/k3d-$(ARCH)-amd64
	chmod a+x local-dev/k3d
endif

# Symlink the installed kubectl client if the correct version is already
# installed, otherwise downloads it.
local-dev/kubectl:
ifeq ($(KUBECTL_VERSION), $(shell kubectl version --short --client 2>/dev/null | sed -E 's/Client Version: v([0-9.]+).*/\1/'))
	$(info linking local kubectl version $(KUBECTL_VERSION))
	ln -s $(shell command -v kubectl) ./local-dev/kubectl
else
	$(info downloading kubectl version $(KUBECTL_VERSION) for $(ARCH))
	curl -Lo local-dev/kubectl https://storage.googleapis.com/kubernetes-release/release/$(KUBECTL_VERSION)/bin/$(ARCH)/amd64/kubectl
	chmod a+x local-dev/kubectl
endif

# Symlink the installed helm client if the correct version is already
# installed, otherwise downloads it.
local-dev/helm/helm:
	@mkdir -p ./local-dev/helm
ifeq ($(HELM_VERSION), $(shell helm version --short --client 2>/dev/null | sed -E 's/v([0-9.]+).*/\1/'))
	$(info linking local helm version $(HELM_VERSION))
	ln -s $(shell command -v helm) ./local-dev/helm
else
	$(info downloading helm version $(HELM_VERSION) for $(ARCH))
	curl -L https://get.helm.sh/helm-$(HELM_VERSION)-$(ARCH)-amd64.tar.gz | tar xzC local-dev/helm --strip-components=1
	chmod a+x local-dev/helm/helm
endif

ifeq ($(DOCKER_DRIVER), btrfs)
# https://github.com/rancher/k3d/blob/master/docs/faq.md
K3D_BTRFS_VOLUME := --volume /dev/mapper:/dev/mapper
else
K3D_BTRFS_VOLUME :=
endif

k3d: local-dev/k3d local-dev/kubectl local-dev/helm/helm
	$(MAKE) local-registry-up
	$(info starting k3d with name $(K3D_NAME))
	$(info Creating Loopback Interface for docker gateway if it does not exist, this might ask for sudo)
ifeq ($(ARCH), darwin)
	if ! ifconfig lo0 | grep $$(docker network inspect bridge --format='{{(index .IPAM.Config 0).Gateway}}') -q; then sudo ifconfig lo0 alias $$(docker network inspect bridge --format='{{(index .IPAM.Config 0).Gateway}}'); fi
endif
	./local-dev/k3d create --wait 0 --publish 18080:80 \
		--publish 18443:443 \
		--api-port 16643 \
		--name $(K3D_NAME) \
		--image docker.io/rancher/k3s:$(K3S_VERSION) \
		--volume $$PWD/local-dev/k3d-registries.yaml:/etc/rancher/k3s/registries.yaml \
		$(K3D_BTRFS_VOLUME) \
		-x --no-deploy=traefik \
		--volume $$PWD/local-dev/k3d-nginx-ingress.yaml:/var/lib/rancher/k3s/server/manifests/k3d-nginx-ingress.yaml
	echo "$(K3D_NAME)" > $@
	export KUBECONFIG="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')"; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" apply -f $$PWD/local-dev/k3d-storageclass-bulk.yaml; \
	$(MAKE) push-docker-host
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' create namespace k8up; \
	local-dev/helm/helm --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --kube-context='$(K3D_NAME)' repo add appuio https://charts.appuio.ch; \
	local-dev/helm/helm --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --kube-context='$(K3D_NAME)' upgrade --install -n k8up k8up appuio/k8up; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' create namespace dioscuri; \
	local-dev/helm/helm --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --kube-context='$(K3D_NAME)' repo add dioscuri https://raw.githubusercontent.com/amazeeio/dioscuri/ingress/charts ; \
	local-dev/helm/helm --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --kube-context='$(K3D_NAME)' upgrade --install -n dioscuri dioscuri dioscuri/dioscuri ; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' create namespace dbaas-operator; \
	local-dev/helm/helm --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --kube-context='$(K3D_NAME)' repo add dbaas-operator https://raw.githubusercontent.com/amazeeio/dbaas-operator/master/charts ; \
	local-dev/helm/helm --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --kube-context='$(K3D_NAME)' upgrade --install -n dbaas-operator dbaas-operator dbaas-operator/dbaas-operator ; \
	local-dev/helm/helm --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --kube-context='$(K3D_NAME)' upgrade --install -n dbaas-operator mariadbprovider dbaas-operator/mariadbprovider -f local-dev/helm-values-mariadbprovider.yml ; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' create namespace lagoon; \
	local-dev/helm/helm --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --kube-context='$(K3D_NAME)' repo add amazeeio https://amazeeio.github.io/charts/; \
	local-dev/helm/helm --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --kube-context='$(K3D_NAME)' upgrade --install -n lagoon lagoon-remote amazeeio/lagoon-remote --set dockerHost.image.name=172.17.0.1:5000/lagoon/docker-host --set dockerHost.registry=172.17.0.1:5000; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' -n lagoon rollout status deployment docker-host -w;
ifeq ($(ARCH), darwin)
	export KUBECONFIG="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')"; \
	KUBERNETESBUILDDEPLOY_TOKEN=$$(local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' -n lagoon describe secret $$(local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' -n lagoon get secret | grep kubernetesbuilddeploy | awk '{print $$1}') | grep token: | awk '{print $$2}'); \
	sed -i '' -e "s/\".*\" # make-kubernetes-token/\"$${KUBERNETESBUILDDEPLOY_TOKEN}\" # make-kubernetes-token/g" local-dev/api-data/03-populate-api-data-kubernetes.gql; \
	DOCKER_IP="$$(docker network inspect bridge --format='{{(index .IPAM.Config 0).Gateway}}')"; \
	sed -i '' -e "s/172\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/$${DOCKER_IP}/g" local-dev/api-data/03-populate-api-data-kubernetes.gql docker-compose.yaml;
else
	export KUBECONFIG="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')"; \
	KUBERNETESBUILDDEPLOY_TOKEN=$$(local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' -n lagoon describe secret $$(local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' -n lagoon get secret | grep kubernetesbuilddeploy | awk '{print $$1}') | grep token: | awk '{print $$2}'); \
	sed -i "s/\".*\" # make-kubernetes-token/\"$${KUBERNETESBUILDDEPLOY_TOKEN}\" # make-kubernetes-token/g" local-dev/api-data/03-populate-api-data-kubernetes.gql; \
	DOCKER_IP="$$(docker network inspect bridge --format='{{(index .IPAM.Config 0).Gateway}}')"; \
	sed -i "s/172\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/$${DOCKER_IP}/g" local-dev/api-data/03-populate-api-data-kubernetes.gql docker-compose.yaml;
endif
	$(MAKE) push-kubectl-build-deploy-dind

.PHONY: push-docker-host
push-docker-host:
	docker pull $(CORE_IMAGE_REPO)/docker-host:${CORE_IMAGE_TAG}
	docker tag $(CORE_IMAGE_REPO)/docker-host:${CORE_IMAGE_TAG} localhost:5000/lagoon/docker-host
	docker push localhost:5000/lagoon/docker-host

.PHONY: push-kubectl-build-deploy-dind
push-kubectl-build-deploy-dind:
	docker pull $(CORE_IMAGE_REPO)/kubectl-build-deploy-dind:${CORE_IMAGE_TAG}
	docker tag $(CORE_IMAGE_REPO)/kubectl-build-deploy-dind:${CORE_IMAGE_TAG} localhost:5000/lagoon/kubectl-build-deploy-dind
	docker push localhost:5000/lagoon/kubectl-build-deploy-dind

.PHONY: rebuild-push-kubectl-build-deploy-dind
rebuild-push-kubectl-build-deploy-dind:
	rm -rf build/kubectl-build-deploy-dind
	$(MAKE) push-kubectl-build-deploy-dind

k3d-kubeconfig:
	export KUBECONFIG="$$(./local-dev/k3d get-kubeconfig --name=$$(cat k3d))"

k3d-dashboard:
	export KUBECONFIG="$$(./local-dev/k3d get-kubeconfig --name=$$(cat k3d))"; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-rc2/aio/deploy/recommended/00_dashboard-namespace.yaml; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-rc2/aio/deploy/recommended/01_dashboard-serviceaccount.yaml; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-rc2/aio/deploy/recommended/02_dashboard-service.yaml; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-rc2/aio/deploy/recommended/03_dashboard-secret.yaml; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-rc2/aio/deploy/recommended/04_dashboard-configmap.yaml; \
	echo '{"apiVersion": "rbac.authorization.k8s.io/v1","kind": "ClusterRoleBinding","metadata": {"name": "kubernetes-dashboard","namespace": "kubernetes-dashboard"},"roleRef": {"apiGroup": "rbac.authorization.k8s.io","kind": "ClusterRole","name": "cluster-admin"},"subjects": [{"kind": "ServiceAccount","name": "kubernetes-dashboard","namespace": "kubernetes-dashboard"}]}' | local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' -n kubernetes-dashboard apply -f - ; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-rc2/aio/deploy/recommended/06_dashboard-deployment.yaml; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-rc2/aio/deploy/recommended/07_scraper-service.yaml; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-rc2/aio/deploy/recommended/08_scraper-deployment.yaml; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' -n kubernetes-dashboard patch deployment kubernetes-dashboard --patch '{"spec": {"template": {"spec": {"containers": [{"name": "kubernetes-dashboard","args": ["--auto-generate-certificates","--namespace=kubernetes-dashboard","--enable-skip-login"]}]}}}}'; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' -n kubernetes-dashboard rollout status deployment kubernetes-dashboard -w; \
	open http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/ ; \
	local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' proxy

k8s-dashboard:
	kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-rc2/aio/deploy/recommended.yaml; \
	kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' -n kubernetes-dashboard rollout status deployment kubernetes-dashboard -w; \
	echo -e "\nUse this token:"; \
	kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' -n lagoon describe secret $$(local-dev/kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' -n lagoon get secret | grep kubernetesbuilddeploy | awk '{print $$1}') | grep token: | awk '{print $$2}'; \
	open http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/ ; \
	kubectl --kubeconfig="$$(./local-dev/k3d get-kubeconfig --name='$(K3D_NAME)')" --context='$(K3D_NAME)' proxy

# Stop k3d
.PHONY: k3d/stop
k3d/stop: local-dev/k3d
	./local-dev/k3d delete --name=$$(cat k3d) || true
	rm -f k3d

# Stop All k3d
.PHONY: k3d/stopall
k3d/stopall: local-dev/k3d
	./local-dev/k3d delete --all || true
	rm -f k3d

# Stop k3d, remove downloaded k3d
.PHONY: k3d/clean
k3d/clean: k3d/stop
	rm -rf ./local-dev/k3d

# Stop All k3d, remove downloaded k3d
.PHONY: k3d/cleanall
k3d/cleanall: k3d/stopall
	rm -rf ./local-dev/k3d

# Configures Kubernetes to use with Lagoon
.PHONY: kubernetes-lagoon-setup
kubernetes-lagoon-setup:
	kubectl create namespace lagoon; \
	local-dev/helm/helm upgrade --install -n lagoon lagoon-remote ./charts/lagoon-remote; \
	echo -e "\n\nAll Setup, use this token as described in the Lagoon Install Documentation:";
	$(MAKE) kubernetes-get-kubernetesbuilddeploy-token

.PHONY: kubernetes-get-kubernetesbuilddeploy-token
kubernetes-get-kubernetesbuilddeploy-token:
	kubectl -n lagoon describe secret $$(kubectl -n lagoon get secret | grep kubernetesbuilddeploy | awk '{print $$1}') | grep token: | awk '{print $$2}'
