include scripts/config.sh
export

VERSION ?= 0.7.0

.PHONY: test app dmg appcast release install screenshots mascots

test:
	bash scripts/test.sh

app:
	bash scripts/build-app.sh $(VERSION)

dmg:
	bash scripts/make-dmg.sh $(VERSION)

# Redraws the built-in mascots into Sources/PRPulse/Mascots (needs node).
mascots:
	node scripts/make-mascots.mjs

# The DMG plus the signed update feed, ready to attach to a GitHub release.
appcast: dmg
	bash scripts/make-appcast.sh $(VERSION)

release: appcast
	@echo "attach build/$(APP_NAME)-$(VERSION).dmg and build/feed/appcast.xml to the v$(VERSION) release"

install: app
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "build/$(APP_NAME).app" /Applications/
	@echo "installed: /Applications/$(APP_NAME).app"

# Renders the README pictures with fake data (English UI) into docs/images.
screenshots: app
	rm -rf build/screenshots
	PRPULSE_DEMO=pending PRPULSE_SNAPSHOT_DIR=build/screenshots PRPULSE_SNAPSHOT_STYLE=readme \
		"build/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" -AppleLanguages "(en)"
	mkdir -p docs/images
	cp build/screenshots/*.png docs/images/
