PREFIX ?= $(HOME)/.local
SWIFT_BUILD_ROOT ?= $(CURDIR)/.build/msl-settings
XCODE_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
SWIFT_ENV = DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" CLANG_MODULE_CACHE_PATH="$(SWIFT_BUILD_ROOT)/module-cache" SWIFT_MODULECACHE_PATH="$(SWIFT_BUILD_ROOT)/module-cache"

.PHONY: test cli-test app-test lint install app-build app-bundle machine-image

test: cli-test app-test

cli-test:
	./tests/test-msl-arm.sh

app-test:
	mkdir -p "$(SWIFT_BUILD_ROOT)/module-cache"
	$(SWIFT_ENV) xcrun swift test --disable-sandbox --package-path App/MSLSettings --scratch-path "$(SWIFT_BUILD_ROOT)/swift"

lint:
	bash -n ./bin/msl-arm ./tests/test-msl-arm.sh ./scripts/build-app.sh ./scripts/package-app.sh
	shellcheck ./bin/msl-arm ./tests/test-msl-arm.sh ./scripts/build-app.sh ./scripts/package-app.sh

install:
	mkdir -p "$(PREFIX)/bin"
	install -m 0755 ./bin/msl-arm "$(PREFIX)/bin/msl-arm"

app-build:
	mkdir -p "$(SWIFT_BUILD_ROOT)/module-cache"
	$(SWIFT_ENV) xcrun swift build --disable-sandbox --package-path App/MSLSettings --scratch-path "$(SWIFT_BUILD_ROOT)/swift"

app-bundle:
	./scripts/package-app.sh

machine-image:
	container build --tag local/msl-ubuntu-machine:24.04 images/ubuntu-machine
