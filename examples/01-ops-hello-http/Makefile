IMAGE_NAME    := ops-hello-http
INSTANCE_NAME := ops-hello-http

.PHONY: image deploy destroy clean

image:
	go build -o hello-http main.go
	ops image create -t hetzner -c config.json hello-http

deploy: image
	-ops instance delete $(INSTANCE_NAME) -t hetzner -c config.json
	ops instance create $(IMAGE_NAME) -t hetzner -c config.json -p 8080

destroy:
	-ops instance delete $(INSTANCE_NAME) -t hetzner -c config.json
	-ops image delete $(IMAGE_NAME) -t hetzner -c config.json

clean:
	-ops instance delete $(INSTANCE_NAME) -t hetzner -c config.json
	-ops image delete $(IMAGE_NAME) -t hetzner -c config.json
