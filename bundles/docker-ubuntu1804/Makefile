DATE=$(shell date +%Y%m%d)

build:
	docker build -t quay.io/replicated/docker-packages:ubuntu-1804-v18.06.3-${DATE} .

push:
	docker push quay.io/replicated/docker-packages:ubuntu-1804-v18.06.3-${DATE}

print_layer_id:
	@docker save quay.io/replicated/docker-packages:ubuntu-1804-v18.06.3-${DATE} | tar -t | grep layer.tar | cut -d'/' -f1

# this gets run by airgap install script
unpack_example:
	rm -rf image/
	mkdir -p image/
	docker save quay.io/replicated/docker-packages:ubuntu-1804-v18.06.3-${DATE} > image.tar
	tar xvf image.tar -C image
	tar xvf image/657058e69949840931db9a359a4479856441bb607df4e13350646c66e1162c98/layer.tar
