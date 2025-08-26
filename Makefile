.PHONY: build test cs-cc worker clean version

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -X 'main.version=$(VERSION)'

build:
	go build -ldflags "$(LDFLAGS)" ./...

test:
	go test ./...

cs-cc:
	mkdir -p bin
	GOOS=linux GOARCH=amd64 go build -ldflags "$(LDFLAGS)" -o bin/cs-cc ./cmd/cs-cc

worker:
	mkdir -p bin
	GOOS=linux GOARCH=amd64 go build -ldflags "$(LDFLAGS)" -o bin/worker ./cmd/worker

clean:
	rm -rf bin


