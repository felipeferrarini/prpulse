include scripts/config.sh
export

VERSION ?= 0.1.0

.PHONY: test app dmg install

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
