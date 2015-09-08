NS = $(DOCKER_NS)
VERSION ?= latest

REPO = mongo-replset
NAME = mongo-replset

.PHONY: build push shell release

build:
	docker build -t $(NS)/$(REPO):$(VERSION) .

push:
	docker push $(NS)/$(REPO):$(VERSION)

shell:
	docker run --rm --name $(NAME) -i -t --env-file $(NS)/$(REPO)^:$(VERSION) /bin/bash

release: build
	make push -e VERSION=$(VERSION)

default: build
