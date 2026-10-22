PREFIX ?= $(HOME)/.local
APP := build/Phew.app
VERSION := $(shell sed -n 's/.*version = "\(.*\)"/\1/p' Sources/PhewCore/AppInfo.swift)

.PHONY: build test install app run-app icons

build:
	swift build -c release

test:
	swift test

install: build
	mkdir -p $(PREFIX)/bin
	cp .build/release/phew $(PREFIX)/bin/phew

app:
	swift build -c release --product PhewApp
	swift build -c release --product phew
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/PhewApp .build/release/phew $(APP)/Contents/MacOS/
	cp App/AppIcon.icns $(APP)/Contents/Resources/
	sed 's/VERSION/$(VERSION)/' App/Info.plist > $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

run-app: app
	open $(APP)

icons:
	swift scripts/make-icons.swift
