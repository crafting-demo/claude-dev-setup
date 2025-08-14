.PHONY: build test cs-cc worker clean

build:
    go build ./...

test:
    go test ./...

cs-cc:
    mkdir -p bin
    GOOS=linux GOARCH=amd64 go build -o bin/cs-cc ./cmd/cs-cc

worker:
    mkdir -p bin
    GOOS=linux GOARCH=amd64 go build -o bin/worker ./cmd/worker

clean:
    rm -rf bin


