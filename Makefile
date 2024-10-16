.PHONY: deps build dev shell shell_composer shell_composer_dex shell_composer_linux shell_composer_prod test run

SHELL := /bin/bash
#paths within WSL start with /mnt/c/...
#docker does not recognize this fact
#this strips the first 5 characters (leaving /c/...) if the kernel releaser is Microsoft
ifeq ($(shell uname -r | tail -c 10), Microsoft)
	BUILD_DIR := $(shell pwd | cut -c 5-)
else
	BUILD_DIR := $(shell pwd)
endif

deps:
	pip3 install -r requirements.txt

build:
	docker build --pull -t install-scripts -f deploy/Dockerfile.prod .

dev:
	docker build -t install-scripts-dev .

shell:
	docker run -it --rm --name install-scripts \
		-p 8090:5000/tcp \
		-e ENVIRONMENT=dev \
		-e REPLICATED_INSTALL_URL=http://192.168.100.100:8090 \
		-e MYSQL_USER=replicated \
		-e MYSQL_PASS=password \
		-e MYSQL_HOST=192.168.100.100 \
		-e MYSQL_PORT=3306 \
		-e MYSQL_DB=replicated \
		-v $(BUILD_DIR):/usr/src/app \
		install-scripts-dev \
		/bin/bash

# shell for running mysql from saas composer
shell_composer:
	docker run -it --rm --name install-scripts \
		-p 8090:5000/tcp \
		-e ENVIRONMENT=dev \
		-e REPLICATED_INSTALL_URL=http://localhost:8090 \
		-e GRAPHQL_PREM_ENDPOINT=http://172.17.0.1:8033/graphql  \
		-e REGISTRY_ENDPOINT=registry.staging.replicated.com \
		-e MYSQL_USER=replicated \
		-e MYSQL_PASS=password \
		-e MYSQL_HOST=172.17.0.1 \
		-e MYSQL_PORT=3306 \
		-e MYSQL_DB=replicated \
		-v $(BUILD_DIR):/usr/src/app \
		install-scripts-dev \
		/bin/bash

# shell for running mysql from saas composer, but scripts will
# delegate to prod for other things like docker-install.sh
shell_composer_prod:
	docker run -it --rm --name install-scripts \
		-p 8090:5000/tcp \
		-e ENVIRONMENT=dev \
		-e REPLICATED_INSTALL_URL=https://get.replicated.com \
		-e MYSQL_USER=replicated \
		-e MYSQL_PASS=password \
		-e MYSQL_HOST=172.17.0.1 \
		-e MYSQL_PORT=3306 \
		-e MYSQL_DB=replicated \
		-v $(BUILD_DIR):/usr/src/app \
		install-scripts-dev \
		/bin/bash

# shell for running mysql from saas composer, but scripts will
# delegate to dex.ngrok.io for other things like docker-install.sh
shell_composer_dex:
	docker run -it --rm --name install-scripts \
		-p 8090:5000/tcp \
		-e ENVIRONMENT=dev \
		-e REPLICATED_INSTALL_URL=https://dex.ngrok.io \
		-e MYSQL_USER=replicated \
		-e MYSQL_PASS=password \
		-e MYSQL_HOST=172.17.0.1 \
		-e MYSQL_PORT=3306 \
		-e MYSQL_DB=replicated \
		-v $(BUILD_DIR):/usr/src/app \
		install-scripts-dev \
		/bin/bash

# shell for running mysql from saas composer, but scripts will
# delegate to kevin.ngrok.io for other things like docker-install.sh
shell_composer_kevin:
	docker run -it --rm --name install-scripts \
		-p 8090:5000/tcp \
		-e ENVIRONMENT=dev \
		-e REPLICATED_INSTALL_URL=https://kevin109104.ngrok.io \
		-e MYSQL_USER=replicated \
		-e MYSQL_PASS=password \
		-e MYSQL_HOST=172.17.0.1 \
		-e MYSQL_PORT=3306 \
		-e MYSQL_DB=replicated \
		-v $(BUILD_DIR):/usr/src/app \
		install-scripts-dev \
		/bin/bash

# shell for running mysql from saas composer on linux
shell_composer_linux:
	docker run -it --rm --name install-scripts \
		-p 8090:5000/tcp \
		-e ENVIRONMENT=dev \
		-e REPLICATED_INSTALL_URL=http://127.0.0.1:8090 \
		-e MYSQL_USER=replicated \
		-e MYSQL_PASS=password \
		-e MYSQL_HOST=172.17.0.1 \
		-e MYSQL_PORT=3306 \
		-e MYSQL_DB=replicated \
		-v $(BUILD_DIR):/usr/src/app \
		install-scripts-dev \
		/bin/bash
test:
	python3 -m pytest -v tests
	./test.sh

run:
	/dcg --raw > install_scripts/templates/swarm/docker-compose-generate-safe.sh
	python3 main.py

.PHONY: scan
scan: build
	curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b bin
	./bin/grype --fail-on medium --only-fixed install-scripts:latest
