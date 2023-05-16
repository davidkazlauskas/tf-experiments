VERSION := 1.0.0
IMAGE_NAME := gopoller

build:
	go build -o main main.go
	docker build -t $(IMAGE_NAME):$(VERSION) .

clean:
	rm -f main
	docker rmi -f $(IMAGE_NAME):$(VERSION)
