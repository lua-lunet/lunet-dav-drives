SHELL := /bin/sh

ROOT := $(CURDIR)
TOOLS_DIR := $(ROOT)/.tools
ROCKS_DIR := $(TOOLS_DIR)/rocks
BUILD_DIR := $(ROOT)/build
TARGET_DIR := $(ROOT)/target

LUNET_VERSION := v0.18.2
LUNET_DIR := $(ROOT)/.lunet/$(LUNET_VERSION)
LUNET_RUN := $(LUNET_DIR)/lunet-run
LUNET_FETCHER := $(ROOT)/lunet_fetch_release_$(LUNET_VERSION).lua

HURL_VERSION := 8.0.1
HURL_DIR := $(TOOLS_DIR)/hurl/$(HURL_VERSION)/hurl-$(HURL_VERSION)-aarch64-apple-darwin
HURL := $(HURL_DIR)/bin/hurl

LUAROCKS := luarocks --lua-version=5.1 --tree $(ROCKS_DIR)
# luarocks generates self-contained wrappers that put the tree on package.path.
CYAN := $(ROCKS_DIR)/bin/cyan
TESTED := $(ROCKS_DIR)/bin/tested

APP := $(BUILD_DIR)/server.lua
BUILD_LUA_PATH := $(BUILD_DIR)/?.lua;$(BUILD_DIR)/?/init.lua;;

APP_HOST ?= 127.0.0.1
APP_PORT ?= 18080
SERVER_PID := $(TARGET_DIR)/server.pid
SERVER_LOG := $(TARGET_DIR)/server.log

.PHONY: help init deps check-s3 build unit start stop restart status test e2e e2e-up e2e-down db-reset clean

# A bare `make` explains itself rather than doing anything.
.DEFAULT_GOAL := help

-include .env

# The server and psql read their configuration from the environment, so .env
# values must reach recipe subprocesses rather than staying make-only.
export APP_HOST APP_PORT
export PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD
export S3_ENDPOINT S3_BUCKET S3_REGION S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY

help:
	@printf '%s\n' \
		'lunet-dav-drives - a document store built around flat shared Drives.' \
		'' \
		'  First run:   make init     then   make test' \
		'' \
		'BUILD AND TEST FLOW' \
		'' \
		'  Teal source' \
		'    -> Cyan build' \
		'    -> tested unit smoke' \
		'    -> Lunet runs generated Lua from build/' \
		'    -> Hurl is the final DoD' \
		'' \
		'  Cyan compiles every .tl file into build/. Lunet only ever runs' \
		'  build/server.lua and tested only ever runs build/tests; nothing runs' \
		'  a .tl file directly. The language is type checked, so the compiler' \
		'  carries the load that tests would otherwise carry, and Hurl against' \
		'  the real running server is the measure of done.' \
		'' \
		'EVERYDAY' \
		'' \
		'  make init       Install and check every dependency: build, test, and' \
		'                  runtime. Safe to rerun - it only fetches what is' \
		'                  missing. Seeds .env from .env.example.' \
		'  make test       The whole chain above. Begins with a fast check of the' \
		'                  runtime dependencies, which tells you to run' \
		'                  make init if one of them is missing.' \
		'  make help       This message. Also what a bare make prints.' \
		'' \
		'ONE STEP AT A TIME' \
		'' \
		'  make deps       Fast fail-fast check of runtime dependencies only.' \
		'  make build      Compile Teal into build/ with Cyan. Type errors and' \
		'                  unused locals fail the build here.' \
		'  make unit       Run the tested unit smoke over the compiled Lua.' \
		'  make e2e        Load the schema, seed, start the server, run the Hurl' \
		'                  specs in spec/, then tear it all down again.' \
		'' \
		'THE RUNNING SERVER' \
		'' \
		'  make start      Start the server from build/ and wait for /health.' \
		'  make stop       Stop the server. Refuses to kill a non-lunet process.' \
		'  make restart    stop then start.' \
		'  make status     Report the pid and whether /health answers.' \
		'' \
		'STACK AND DATA' \
		'' \
		'  make e2e-up     Bring up postgres and garage and leave them running.' \
		'  make e2e-down   Tear the docker stack down.' \
		'  make db-reset   Drop the public schema and reload sql/schema.sql.' \
		'                  Destroys all local data.' \
		'' \
		'HOUSEKEEPING' \
		'' \
		'  make clean      Remove build/, target/, and the downloaded tools in' \
		'                  .tools/. Run make init again afterwards.' \
		'' \
		'CONFIGURATION' \
		'' \
		'  Settings come from .env, which make init seeds from .env.example.' \
		'  The docker ports there are deliberately distinct from other' \
		'  lunet-dav stacks so several can run on one machine at once.' \
		'' \
		'  Server            http://$(APP_HOST):$(APP_PORT)' \
		'  Toolchain         .lunet/ (lunet $(LUNET_VERSION)), .tools/ (hurl $(HURL_VERSION), cyan, tested)' \
		'  Generated Lua     build/' \
		'  Schema            sql/schema.sql' \
		'  HTTP contracts    openapi.yaml (native), openapi/ (NCe31 work-alike)' \
		'' \
		'  KEEP_STACK=1 make e2e   Leave the server and containers up afterwards.'

# ---------------------------------------------------------------------------
# init installs or verifies every dependency: build, test, and runtime.
# When adding a dependency, add its bootstrap here.
# ---------------------------------------------------------------------------
init:
	@set -e; \
	uname_s=$$(uname -s); uname_m=$$(uname -m); \
	if [ "$$uname_s" != "Darwin" ] || [ "$$uname_m" != "arm64" ]; then \
		echo "ERROR: init is pinned to macOS/Darwin arm64."; \
		echo "Install the local prerequisites, then rerun init on Apple Silicon."; \
		exit 1; \
	fi; \
	for cmd in curl tar luarocks luajit psql docker openssl shasum; do \
		command -v $$cmd >/dev/null 2>&1 || { echo "ERROR: missing $$cmd; install it and rerun make init"; exit 1; }; \
	done; \
	mkdir -p $(TOOLS_DIR)/downloads $(ROCKS_DIR) $(TARGET_DIR) $(BUILD_DIR); \
	luajit $(LUNET_FETCHER); \
	if [ ! -x "$(HURL)" ]; then \
		echo "installing hurl $(HURL_VERSION)"; \
		tmp=$$(mktemp -d); \
		curl -fsSL -o "$$tmp/hurl.tar.gz" "https://github.com/Orange-OpenSource/hurl/releases/download/$(HURL_VERSION)/hurl-$(HURL_VERSION)-aarch64-apple-darwin.tar.gz"; \
		rm -rf "$(HURL_DIR)"; mkdir -p "$(TOOLS_DIR)/hurl/$(HURL_VERSION)"; \
		tar -xzf "$$tmp/hurl.tar.gz" -C "$(TOOLS_DIR)/hurl/$(HURL_VERSION)"; \
		rm -rf "$$tmp"; \
	fi; \
	for rock in tl cyan tested; do \
		if ! $(LUAROCKS) list --porcelain $$rock 2>/dev/null | grep -q "^$$rock"; then \
			echo "installing rock $$rock"; \
			$(LUAROCKS) install $$rock; \
		fi; \
	done; \
	if ! luajit -e 'require("ffi").load("sodium")' >/dev/null 2>&1; then \
		echo "installing libsodium"; \
		command -v brew >/dev/null 2>&1 || { echo "ERROR: libsodium is missing and brew is unavailable"; exit 1; }; \
		brew list libsodium >/dev/null 2>&1 || brew install libsodium; \
	fi; \
	if [ ! -f .env ] && [ -f .env.example ]; then cp .env.example .env; fi; \
	$(MAKE) deps

# ---------------------------------------------------------------------------
# deps is the fast fail-fast check that runs first in make test.
#
# It covers runtime/business dependencies only: things whose absence would
# otherwise surface much later as a confusing failure inside the server, the
# database, or Hurl. Build/test tools (Cyan, tested) are deliberately not
# checked here because their own step fails clearly when they are missing.
# ---------------------------------------------------------------------------
deps:
	@set -e; \
	fail() { echo "ERROR: $$1"; echo "run: make init"; exit 1; }; \
	[ -x "$(LUNET_RUN)" ] || fail "lunet runtime not found at $(LUNET_RUN)"; \
	[ -x "$(HURL)" ] || fail "hurl not found at $(HURL)"; \
	command -v luajit >/dev/null 2>&1 || fail "luajit not on PATH"; \
	luajit -e 'require("ffi").load("sodium")' >/dev/null 2>&1 \
		|| fail "libsodium is not loadable; app/crypto.tl needs it for password digests"; \
	command -v psql >/dev/null 2>&1 || fail "psql not on PATH"; \
	command -v docker >/dev/null 2>&1 || fail "docker not on PATH"; \
	docker info >/dev/null 2>&1 || fail "the docker daemon is not running; postgres and garage come from e2e/docker-compose.yml"; \
	echo "deps ok"

# garage is only reachable once the stack is up, so it is checked here rather
# than in deps, which must stay fast and runnable before anything is running.
check-s3:
	@set -e; \
	curl -fsS "http://127.0.0.1:19011/health" >/dev/null 2>&1 \
		|| { echo "ERROR: the object store is not answering at http://127.0.0.1:19011"; \
		     echo "run: make e2e-up   (or: make init)"; exit 1; }

# ---------------------------------------------------------------------------
# Cyan owns the whole-project compile: Teal in place -> Lua under build/.
# ---------------------------------------------------------------------------
build:
	@set -e; \
	mkdir -p $(BUILD_DIR); \
	$(CYAN) build --prune

unit: build
	@set -e; \
	LUA_PATH='$(BUILD_LUA_PATH)' $(TESTED) $(BUILD_DIR)/tests

test:
	@set -e; \
	$(MAKE) deps; \
	$(MAKE) build; \
	$(MAKE) unit; \
	$(MAKE) e2e

start: build
	@set -e; \
	if [ -f "$(SERVER_PID)" ] && kill -0 "$$(cat "$(SERVER_PID)")" 2>/dev/null; then \
		echo "already running"; \
		exit 0; \
	fi; \
	if lsof -ti tcp:$(APP_PORT) >/dev/null 2>&1; then \
		echo "ERROR: port $(APP_PORT) is already in use"; \
		exit 1; \
	fi; \
	mkdir -p $(TARGET_DIR); \
	nohup "$(LUNET_RUN)" "$(APP)" >"$(SERVER_LOG)" 2>&1 & echo $$! >"$(SERVER_PID)"; \
	for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do \
		curl -fsS "http://$(APP_HOST):$(APP_PORT)/health" >/dev/null 2>&1 && exit 0; \
		sleep 1; \
	done; \
	echo "ERROR: server did not become healthy"; \
	cat "$(SERVER_LOG)"; \
	exit 1

stop:
	@set -e; \
	if [ -f "$(SERVER_PID)" ]; then \
		pid=$$(cat "$(SERVER_PID)"); \
		comm=$$(ps -p "$$pid" -o comm= 2>/dev/null | tr -d ' '); \
		case "$$comm" in \
			*lunet-run*) kill "$$pid" 2>/dev/null || true ;; \
			"") ;; \
			*) echo "refusing to kill non-lunet process $$pid ($$comm)"; exit 1 ;; \
		esac; \
		rm -f "$(SERVER_PID)"; \
	fi

restart: stop start

status:
	@set -e; \
	if [ -f "$(SERVER_PID)" ] && kill -0 "$$(cat "$(SERVER_PID)")" 2>/dev/null; then \
		echo "running pid=$$(cat "$(SERVER_PID)")"; \
		curl -fsS "http://$(APP_HOST):$(APP_PORT)/health" >/dev/null && echo "health=ok" || echo "health=bad"; \
	else \
		echo "stopped"; \
	fi

db-reset:
	@set -e; \
	psql -X -v ON_ERROR_STOP=1 -d "$${PGDATABASE:-lunet_dav_drives}" \
		-c 'DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;'; \
	psql -X -v ON_ERROR_STOP=1 -d "$${PGDATABASE:-lunet_dav_drives}" -f sql/schema.sql

e2e: build
	@./e2e/run-e2e.sh

e2e-up:
	@./e2e/run-e2e.sh up

e2e-down:
	@./e2e/run-e2e.sh down

clean:
	@set -e; \
	rm -rf $(BUILD_DIR) $(TARGET_DIR) $(TOOLS_DIR) $(ROOT)/.lunet/$(LUNET_VERSION)
