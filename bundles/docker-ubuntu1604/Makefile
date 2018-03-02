build:
	docker build -t quay.io/replicated/docker-packages:ubuntu-1604-v1.12.3 .

push:
	docker push quay.io/replicated/docker-packages:ubuntu-1604-v1.12.3

# this gets run by airgap install script
unpack_example:
	rm -rf image/
	mkdir -p image/
	docker save quay.io/replicated/docker-packages:ubuntu-1604-v1.12.3 > image.tar
	tar xvf image.tar -C image
	tar xvf image/450f2fd85ce0cdef364d992c3dd0b2299beb3f0b61e30f1cf4f94409f180e602/layer.tar
	
	
