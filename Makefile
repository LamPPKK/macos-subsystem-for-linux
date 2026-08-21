PREFIX ?= $(HOME)/.local

.PHONY: test lint install

test:
	./tests/test-msl-arm.sh

lint:
	bash -n ./bin/msl-arm ./tests/test-msl-arm.sh
	shellcheck ./bin/msl-arm ./tests/test-msl-arm.sh

install:
	mkdir -p "$(PREFIX)/bin"
	install -m 0755 ./bin/msl-arm "$(PREFIX)/bin/msl-arm"
