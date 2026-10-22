PREFIX ?= $(HOME)/.local
APP := build/Phew.app
VERSION := $(shell sed -n 's/.*version = "\(.*\)"/\1/p' Sources/PhewCore/AppInfo.swift)

.PHONY: build test install app run-app icons release

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

# Universal (arm64 + x86_64) app with the CLI inside, as a zip and a dmg, each with a SHA-256.
DIST := dist
REL := .build/out/Products/Release
release:
	swift build -c release --arch arm64 --arch x86_64 --product PhewApp
	swift build -c release --arch arm64 --arch x86_64 --product phew
	rm -rf $(DIST)
	mkdir -p $(DIST)/Phew.app/Contents/MacOS $(DIST)/Phew.app/Contents/Resources
	cp $(REL)/PhewApp $(REL)/phew $(DIST)/Phew.app/Contents/MacOS/
	cp App/AppIcon.icns $(DIST)/Phew.app/Contents/Resources/
	sed 's/VERSION/$(VERSION)/' App/Info.plist > $(DIST)/Phew.app/Contents/Info.plist
	# Extended attributes (com.apple.provenance) would land in the zip as ._ files, which
	# `unzip` puts inside the bundle and breaks the signature.
	xattr -cr $(DIST)/Phew.app
	codesign --force --deep --sign - $(DIST)/Phew.app
	cd $(DIST) && ditto -c -k --norsrc --noextattr --keepParent Phew.app Phew-$(VERSION).zip
	cd $(DIST) && shasum -a 256 Phew-$(VERSION).zip > Phew-$(VERSION).zip.sha256
	mkdir -p $(DIST)/dmg
	cp -R $(DIST)/Phew.app $(DIST)/dmg/
	ln -s /Applications $(DIST)/dmg/Applications
	hdiutil create -volname "Phew $(VERSION)" -srcfolder $(DIST)/dmg -format UDZO -ov $(DIST)/Phew-$(VERSION).dmg
	rm -rf $(DIST)/dmg
	cd $(DIST) && shasum -a 256 Phew-$(VERSION).dmg > Phew-$(VERSION).dmg.sha256
