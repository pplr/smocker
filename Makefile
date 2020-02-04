APPNAME:=$(shell basename $(shell go list))
VERSION?=snapshot
COMMIT:=$(shell git rev-parse --verify HEAD)
DATE:=$(shell date +%FT%T%z)
RELEASE?=0

GOPATH?=$(shell go env GOPATH)
GO_LDFLAGS+=-X main.appName=$(APPNAME)
GO_LDFLAGS+=-X main.buildVersion=$(VERSION)
GO_LDFLAGS+=-X main.buildCommit=$(COMMIT)
GO_LDFLAGS+=-X main.buildDate=$(DATE)
ifeq ($(RELEASE), 1)
	# Strip debug information from the binary
	GO_LDFLAGS+=-s -w
endif
GO_LDFLAGS:=-ldflags="$(GO_LDFLAGS)"

DOCKER_ACCOUNT:=thiht
DOCKER_IMAGE:=$(DOCKER_ACCOUNT)/$(APPNAME)

# See: https://docs.docker.com/engine/reference/commandline/tag/#extended-description
# A tag name must be valid ASCII and may contain lowercase and uppercase letters, digits, underscores, periods and dashes.
# A tag name may not start with a period or a dash and may contain a maximum of 128 characters.
DOCKER_TAG:=$(shell echo $(VERSION) | tr -cd '[:alnum:]_.-')

LEVEL=debug

SUITE=*.yml

.PHONY: default
default: start

REFLEX=$(GOPATH)/bin/reflex
$(REFLEX):
	go get github.com/cespare/reflex

GOLANGCILINTVERSION:=1.18.0
GOLANGCILINT=$(GOPATH)/bin/golangci-lint
$(GOLANGCILINT):
	curl -fsSL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(GOPATH)/bin v$(GOLANGCILINTVERSION)

VENOM=$(GOPATH)/bin/venom
$(VENOM):
	go install github.com/ovh/venom/cli/venom

.PHONY: start
start: $(REFLEX)
	reflex --start-service \
		--decoration='none' \
		--regex='\.go$$' \
		--inverse-regex='^vendor|node_modules|.cache/' \
		-- go run $(GO_LDFLAGS) main.go --log-level=$(LEVEL) --static-files ./build

.PHONY: build
build:
	go build $(GO_LDFLAGS) -o ./build/$(APPNAME)

.PHONY: lint
lint: $(GOLANGCILINT)
	golangci-lint run

.PHONY: format
format:
	gofmt -s -w .

.PHONY: test
test:
	go test -v ./...

.PHONY: test-integration
test-integration: $(VENOM)
	venom run tests/features/$(SUITE)

.PHONY: docs
docs:
	venom run tests/features/verify_mocks.yml
	yarn docs:generate

.PHONY: clean
clean:
	rm -rf ./build

.PHONY: build-docker
build-docker:
	docker build --build-arg VERSION=$(VERSION) --tag $(DOCKER_IMAGE):latest .
	docker tag $(DOCKER_IMAGE) $(DOCKER_IMAGE):$(DOCKER_TAG)

.PHONY: start-docker
start-docker:
	docker run -d -p 8080:8080 -p 8081:8081 --name $(APPNAME) $(DOCKER_IMAGE):$(DOCKER_TAG)

# The following targets are only available for CI usage

build/smocker.tar.gz:
	$(MAKE) build
	yarn install --frozen-lockfile
	yarn build
	cd build/ ; tar cvf smocker.tar.gz *

.PHONY: release
release: build/smocker.tar.gz

.PHONY: deploy-docker
deploy-docker:
	docker push $(DOCKER_IMAGE):latest
	docker push $(DOCKER_IMAGE):$(DOCKER_TAG)
