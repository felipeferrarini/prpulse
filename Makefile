include scripts/config.sh
export

VERSION ?= 0.2.0

.PHONY: test app dmg install screenshots

test:
	bash scripts/test.sh

app:
	bash scripts/build-app.sh $(VERSION)

dmg:
	bash scripts/make-dmg.sh $(VERSION)

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
