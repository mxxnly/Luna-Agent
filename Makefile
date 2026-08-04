# LunaAgent Makefile — canonical build & test entrypoints

MODULE := github.com/mxxnly/Luna-Agent
VERSION ?= 0.0.1
COMMIT  ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo none)
LDFLAGS := -X $(MODULE)/internal/version.Version=$(VERSION) -X $(MODULE)/internal/version.Commit=$(COMMIT)

DIST := dist
BIN  := $(DIST)/lunaagentd
MACOSX_DEPLOYMENT_TARGET ?= 10.14
export MACOSX_DEPLOYMENT_TARGET

.PHONY: all ci lint test test-race build build-app integration e2e package sign notarize release-smoke clean mockcontrol installer publish-release

all: ci

ci: lint test build integration

lint:
	@command -v golangci-lint >/dev/null 2>&1 && golangci-lint run ./... || go vet ./...

test:
	LUNA_TEST_MODE=1 LUNA_WG_DRY_RUN=1 go test ./... -count=1

test-race:
	LUNA_TEST_MODE=1 LUNA_WG_DRY_RUN=1 go test -race ./... -count=1

build: $(DIST)
	GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o $(DIST)/lunaagentd-arm64 ./cmd/agent
	GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o $(DIST)/lunaagentd-amd64 ./cmd/agent
	lipo -create -output $(BIN) $(DIST)/lunaagentd-arm64 $(DIST)/lunaagentd-amd64
	GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o $(DIST)/luna-wghelper-arm64 ./cmd/wghelper
	GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o $(DIST)/luna-wghelper-amd64 ./cmd/wghelper
	lipo -create -output $(DIST)/luna-wghelper $(DIST)/luna-wghelper-arm64 $(DIST)/luna-wghelper-amd64
	@echo "built $(BIN) + luna-wghelper ($(VERSION)) macosmin=$(MACOSX_DEPLOYMENT_TARGET)"

build-daemon: build

build-app:
	@mkdir -p $(DIST)
	./scripts/build-app.sh $(DIST)

mockcontrol: $(DIST)
	go build -o $(DIST)/mockcontrol ./cmd/mockcontrol

integration: test
	@echo "integration covered by go test ./internal/agent"

e2e: build mockcontrol
	LUNA_TEST_MODE=1 LUNA_WG_DRY_RUN=1 ./scripts/e2e.sh $(DIST)

package: build build-app
	./scripts/package.sh $(DIST)

installer:
	VERSION="$(VERSION)" ./scripts/build_installer.sh

publish-release:
	./scripts/publish-github-release.sh "$(VERSION)"

sign:
	./scripts/sign.sh $(DIST)

notarize:
	./scripts/notarize.sh $(DIST)

release-smoke:
	./scripts/release-smoke.sh

$(DIST):
	mkdir -p $(DIST)

clean:
	rm -rf $(DIST)
