build:
	docker build -t quay.io/replicated/docker-packages:ubuntu-1604-v1.12.3.20180723 .

push:
	docker push quay.io/replicated/docker-packages:ubuntu-1604-v1.12.3.20180723

# this gets run by airgap install script
unpack_example:
	rm -rf image/
	mkdir -p image/
	docker save quay.io/replicated/docker-packages:ubuntu-1604-v1.12.3.20180723 > image.tar
	tar xvf image.tar -C image
	tar xvf image/9d11016cacbae72f929fb839a5ac9c6810f3f9c639a5f140f86792ec4dcb6ceb/layer.tar
	
	
