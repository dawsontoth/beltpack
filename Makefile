REPO := $(shell pwd)

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---- setup ----------------------------------------------------------------

.PHONY: setup-dev
setup-dev: ## Configure this machine for local development (no WING needed)
	./scripts/setup.sh --dev --install

.PHONY: setup
setup: ## Configure the booth Mac for production
	./scripts/setup.sh --production --install

# ---- build ----------------------------------------------------------------

.PHONY: build
build: server web ## Build everything

.PHONY: server
server: ## Build the WING bridge (release)
	cd server && swift build -c release

.PHONY: web
web: ## Install deps and bundle the PWA
	cd web && npm install && npm run build

# Both Xcode projects reference this for signing, and it is gitignored so a
# team id never lands in a public repo. Create it from the example on first
# use, otherwise a fresh clone fails at xcodegen with a confusing error.
ios/Local.xcconfig:
	cp ios/Local.xcconfig.example $@
	@echo "created ios/Local.xcconfig - set DEVELOPMENT_TEAM in it to build for a device"

.PHONY: icons
icons: ## Regenerate every app icon from appicon-raw.png
	./scripts/make-icons.sh

.PHONY: ios
ios: ios/Local.xcconfig ## Regenerate and open the iOS Xcode project
	cd ios && xcodegen generate && open Beltpack.xcodeproj

.PHONY: phone
phone: ios/Local.xcconfig ## Build and install the app on every connected iPhone
	./scripts/install-phone.sh

.PHONY: admin
admin: ## Open the management page
	@open "http://127.0.0.1:$$(grep '^BELTPACK_ADMIN_PORT' .env | sed -E 's/.*="(.*)"/\1/')/" \
		|| echo "start the host first: make mac"

.PHONY: mac
mac: ios/Local.xcconfig ## Build and launch the Mac host app
	cd mac && xcodegen generate
	cd mac && xcodebuild -project BeltpackHost.xcodeproj -scheme BeltpackHost \
		-configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
	@# So the app reads this checkout's .env instead of guessing at three fixed
	@# paths and coming up with no control panel from anywhere else.
	@defaults write org.beltpack.BeltpackHost beltpack.envPath "$(REPO)/.env" 2>/dev/null || true
	open mac/build/Build/Products/Debug/BeltpackHost.app

.PHONY: mac-logs
mac-logs: ## Follow the Mac app's diagnostics
	/usr/bin/log stream --predicate 'subsystem == "org.beltpack"' --style compact

.PHONY: mac-logs-past
mac-logs-past: ## Show past diagnostics, default the last hour (SINCE=30m to change)
	@# `log stream` only shows what happens next, which is no use for working out
	@# why something failed before you thought to look. The unified log kept it.
	/usr/bin/log show --last $(or $(SINCE),1h) \
		--predicate 'subsystem == "org.beltpack"' --style compact

# ---- run locally ----------------------------------------------------------

.PHONY: devices
devices: ## List Core Audio inputs this Mac can see
	cd server && swift run BeltpackBridge --devices

.PHONY: pair
pair: ## Show a pairing code for a volunteer to scan
	./deploy/run.sh pair

.PHONY: up
up: ## Start everything: LiveKit, the token service and the host app
	./scripts/up.sh

.PHONY: down
down: ## Stop everything
	./scripts/down.sh

.PHONY: run-livekit
run-livekit: ## Run the SFU in the foreground
	./deploy/run.sh livekit

.PHONY: run-token
run-token: ## Run the token service in the foreground
	./deploy/run.sh token

.PHONY: run-bridge
run-bridge: server ## Run the WING bridge in the foreground
	./deploy/run.sh bridge

# ---- deploy ---------------------------------------------------------------

.PHONY: autostart
autostart: ## Start beltpack automatically when this Mac comes up
	./scripts/autostart.sh install

.PHONY: autostart-status
autostart-status: ## Is autostart installed, and is everything answering?
	./scripts/autostart.sh status

.PHONY: no-autostart
no-autostart: ## Stop starting automatically
	./scripts/autostart.sh uninstall

.PHONY: logs
logs: ## Tail all service logs
	tail -f logs/*.log

# ---- checks ---------------------------------------------------------------

.PHONY: check
check: ios/Local.xcconfig ## Build everything and lint what can be linted
	cd server && swift build
	cd server && swift test
	cd ios && xcodegen generate
	@# Piping xcodebuild into tail hands the pipeline tail's exit status, so a
	@# failed build reported success and `make check` passed while the Mac app
	@# would not compile. set -o pipefail is the whole fix.
	cd ios && set -o pipefail && xcodebuild -project Beltpack.xcodeproj -scheme Beltpack \
		-destination 'generic/platform=iOS Simulator' \
		-configuration Debug CODE_SIGNING_ALLOWED=NO build | tail -1
	cd ios && set -o pipefail && xcodebuild -project Beltpack.xcodeproj -scheme BeltpackWatch \
		-destination 'generic/platform=watchOS Simulator' \
		-configuration Debug CODE_SIGNING_ALLOWED=NO build | tail -1
	cd mac && xcodegen generate
	cd mac && set -o pipefail && xcodebuild -project BeltpackHost.xcodeproj -scheme BeltpackHost \
		-configuration Debug CODE_SIGNING_ALLOWED=NO build | tail -1
	cd web && npm install && npm run build && npm test
	node --check token/server.mjs
	bash -n deploy/run.sh
	@for f in deploy/launchd/*.plist; do plutil -lint "$$f"; done
	@echo "all checks passed"

.PHONY: clean
clean: ## Remove build output
	rm -rf server/.build web/dist web/node_modules \
		ios/Beltpack.xcodeproj ios/Info.plist \
		mac/BeltpackHost.xcodeproj mac/Info.plist mac/build
