PREFIX ?= $(HOME)/.local

.PHONY: build test install

build:
	swift build -c release

test:
	swift test

install: build
	mkdir -p $(PREFIX)/bin
	cp .build/release/phew $(PREFIX)/bin/phew
