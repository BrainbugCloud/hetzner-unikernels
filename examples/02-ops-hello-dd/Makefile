IMAGE_NAME := ops-hello-dd
IMAGE_SRC  := $(HOME)/.ops/images/$(IMAGE_NAME)
IMAGE_OUT  := image/$(IMAGE_NAME).img

.PHONY: build run image clean

build:
	go build -o hello-dd main.go
	ops build -t hetzner hello-dd -c config.json

run:
	ops run main.go -c config.json -p 8080

image: build
	mkdir -p image
	cp $(IMAGE_SRC) $(IMAGE_OUT)
	@echo "Image: $(IMAGE_OUT) ($$(du -h $(IMAGE_OUT) | cut -f1))"

clean:
	rm -rf image/
