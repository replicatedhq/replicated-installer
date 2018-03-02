
build:
	docker build -t install-scripts -f deploy/Dockerfile.prod .

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
		-v "`pwd`":/usr/src/app \
		install-scripts-dev \
		/bin/bash

# shell for running mysql from saas composer
shell_composer:
	docker run -it --rm --name install-scripts \
		-p 8090:5000/tcp \
		-e ENVIRONMENT=dev \
		-e REPLICATED_INSTALL_URL=http://192.168.50.1:8090 \
		-e MYSQL_USER=replicated \
		-e MYSQL_PASS=password \
		-e MYSQL_HOST=172.17.0.1 \
		-e MYSQL_PORT=3306 \
		-e MYSQL_DB=replicated \
		-v "`pwd`":/usr/src/app \
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
		-v "`pwd`":/usr/src/app \
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
		-v "`pwd`":/usr/src/app \
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
		-v "`pwd`":/usr/src/app \
		install-scripts-dev \
		/bin/bash
test:
	python -m pytest -v tests
	./test.sh

run:
	python main.py
