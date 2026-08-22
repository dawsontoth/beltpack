REPO := $(shell pwd)
AGENTS := $(HOME)/Library/LaunchAgents

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

.PHONY: ios
ios: ios/Local.xcconfig ## Regenerate and open the iOS Xcode project
	cd ios && xcodegen generate && open Beltpack.xcodeproj

.PHONY: mac
mac: ios/Local.xcconfig ## Build and launch the Mac host app
	cd mac && xcodegen generate
	cd mac && xcodebuild -project BeltpackHost.xcodeproj -scheme BeltpackHost \
		-configuration Debug -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
	open mac/build/Build/Products/Debug/BeltpackHost.app

.PHONY: mac-logs
mac-logs: ## Follow the Mac app's diagnostics
	/usr/bin/log stream --predicate 'subsystem == "org.beltpack"' --style compact

# ---- run locally ----------------------------------------------------------

.PHONY: devices
devices: ## List Core Audio inputs this Mac can see
	cd server && swift run BeltpackBridge --devices

.PHONY: pair
pair: ## Show a pairing code for a volunteer to scan
	./deploy/run.sh pair

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

.PHONY: install-agents
install-agents: ## Install LaunchAgents pointed at this checkout
	@mkdir -p $(AGENTS) logs
	@for svc in livekit token bridge; do \
		sed 's|REPO|$(REPO)|g' deploy/launchd/org.beltpack.$$svc.plist \
			> $(AGENTS)/org.beltpack.$$svc.plist; \
		echo "installed $(AGENTS)/org.beltpack.$$svc.plist"; \
	done
	@echo
	@echo "Now load them:"
	@echo "  for s in livekit token bridge; do launchctl bootstrap gui/\$$(id -u) $(AGENTS)/org.beltpack.\$$s.plist; done"

.PHONY: uninstall-agents
uninstall-agents: ## Unload and remove the LaunchAgents
	@for svc in livekit token bridge; do \
		launchctl bootout gui/$$(id -u)/org.beltpack.$$svc 2>/dev/null || true; \
		rm -f $(AGENTS)/org.beltpack.$$svc.plist; \
	done
	@echo "removed"

.PHONY: logs
logs: ## Tail all service logs
	tail -f logs/*.log

# ---- checks ---------------------------------------------------------------

.PHONY: check
check: ios/Local.xcconfig ## Build everything and lint what can be linted
	cd server && swift build
	cd server && swift test
	cd ios && xcodegen generate
	cd mac && xcodegen generate
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
