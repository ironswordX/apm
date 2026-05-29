ROOT := $(shell pwd)

MUSL_CC := x86_64-alpine-linux-musl-cc
MUSL_CXX := x86_64-alpine-linux-musl-g++

DIST := $(ROOT)/dist

LIBLUA := /usr/lib/lua5.5/liblua.a
LIBLUV := $(ROOT)/luv/build/libluv.a
LIBUV  := $(ROOT)/luv/build/deps/libuv/libuv.a

.PHONY: all luv clean

all: luv apm

luv:
	git submodule update --init --recursive
	$(MAKE) -C luv \
		CC=$(MUSL_CC) \
		CXX=$(MUSL_CXX) \
		BUILD_STATIC_LIBS=on \
		WITH_LUA_ENGINE=Lua

apm: luv
	mkdir -p $(DIST)
	cd src && \
	CC=$(MUSL_CC) CXX=$(MUSL_CXX) luastatic \
		apm.lua colors.lua \
		$(LIBLUA) $(LIBLUV) $(LIBUV) \
		-I/usr/include/lua5.5 \
		-lpthread -ldl -lm --static \
		-static -no-pie -fno-pie

	rm -f src/apm.luastatic.c
	mv src/apm $(DIST)/apm

clean:
	rm -rf dist
