ROOT := $(shell pwd)

MUSL_CC := x86_64-alpine-linux-musl-cc
MUSL_CXX := x86_64-alpine-linux-musl-g++

BUILD := $(ROOT)/build
DIST := $(ROOT)/dist

LIBLUA := /usr/lib/lua5.5/liblua.a
LIBLUV := $(ROOT)/luv/build/libluv.a
LIBUV  := $(ROOT)/luv/build/deps/libuv/libuv.a

.PHONY: all luv clean

all: check-deps luv apm

check-deps:
	@if ! command -v luarocks >/dev/null 2>&1; then \
		echo "luarocks is not installed."; \
		exit 1; \
	fi; \
	check() { \
		pkg="$$1"; \
		if ! luarocks list "$$pkg" 2>/dev/null | grep -q "$$pkg"; then \
			echo "luarocks package $$pkg is NOT installed"; \
			exit 1; \
		fi; \
	}; \
	check dkjson; \
	check argparse
	
luv:
	git submodule update --init --recursive
	LDFLAGS="-Wl,--gc-sections" $(MAKE) -C luv \
		CC=$(MUSL_CC) \
		CXX=$(MUSL_CXX) \
		BUILD_STATIC_LIBS=on \
		WITH_LUA_ENGINE=Lua
		-Oz -flto

apm: luv
	mkdir -p $(BUILD)
	mkdir -p $(DIST)
	
	cd src/ && \
	CC=$(MUSL_CC) CXX=$(MUSL_CXX) luastatic \
		$(BUILD)/apm.luac \
		$(LIBLUA) $(LIBLUV) $(LIBUV) \
		-I/usr/include/lua5.5 \
		-lpthread -ldl -lm -static -no-pie -fno-pie -flto

	rm -rf $(BUILD)
	
	rm -f src/apm.luastatic.c
	mv src/apm $(DIST)/apm
	strip dist/apm

clean:
	rm -rf build
	rm -rf dist
