#!/bin/bash
# build dependencies:
# lua 5.5, luarocks, argparse (from luarocks), dkjson (from luarocks)
ROOT=$(pwd)

# clean up any previous builds
rm -rf "$ROOT/dist/"
mkdir "$ROOT/dist/"

# pull luv
git submodule update --init --recursive

# build deps
cd "$ROOT/luv/"
CC="x86_64-alpine-linux-musl-cc" CXX="x86_64-alpine-linux-musl-g++" BUILD_STATIC_LIBS=on WITH_LUA_ENGINE=Lua make

LIBLUV="$ROOT/luv/build/libluv.a"
LIBUV="$ROOT/luv/build/deps/libuv/libuv.a"
LIBLUA="/usr/lib/lua5.5/liblua.a"

# build
cd "$ROOT/src/"
CC="x86_64-alpine-linux-musl-cc" CXX="x86_64-alpine-linux-musl-g++" luastatic apm.lua colors.lua \
  "$LIBLUA" \
  "$LIBLUV" \
  "$LIBUV" \
  -I/usr/include/lua5.5 \
  -lpthread -ldl -lm --static

# delete unneeded artifacts
rm apm.luastatic.c

# move to dist folder
mv apm "$ROOT/dist/"
cd "$ROOT"
exit
