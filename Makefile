# Copyright © Tavian Barnes <tavianator@tavianator.com>
# SPDX-License-Identifier: 0BSD

# This Makefile implements the configuration and build steps for bfs.  It is
# portable to both GNU make and the BSD make implementations (how that works
# is documented below).  To build bfs, run
#
#     $ make config
#     $ make

# The default build target
default: bfs
.PHONY: default

# BSD make will chdir into ${.OBJDIR} by default, unless we tell it not to
.OBJDIR: .

# We don't use any suffix rules
.SUFFIXES:

# GNU make has $^ for the full list of targets, while BSD make has $> and the
# long-form ${.ALLSRC}.  We could write $^ $> to get them both, but that would
# break if one of them implemented support for the other.  So instead, bring
# BSD's ${.ALLSRC} to GNU.
.ALLSRC ?= $^

# Platform detection
OS != uname
ARCH != uname -m

# For out-of-tree builds, e.g.
#
#     $ make config BUILDDIR=/path/to/build/dir
#     $ make BUILDDIR=/path/to/build/dir
BUILDDIR ?= .

# Shorthand for build subdirectories
BIN := ${BUILDDIR}/bin
GEN := ${BUILDDIR}/gen
OBJ := ${BUILDDIR}/obj

# GNU make strips a leading ./ from target names, so do the same for BSD make
BIN := ${BIN:./%=%}
GEN := ${GEN:./%=%}
OBJ := ${OBJ:./%=%}

# Installation paths
DESTDIR ?=
PREFIX ?= /usr
MANDIR ?= ${PREFIX}/share/man

# Configurable executables; can be overridden with
#
#     $ make config CC=clang
CC ?= cc
INSTALL ?= install
MKDIR ?= mkdir -p
PKG_CONFIG ?= pkg-config
RM ?= rm -f

# Configurable flags

CPPFLAGS ?=
CFLAGS ?= \
    -g \
    -Wall \
    -Wformat=2 \
    -Werror=implicit \
    -Wimplicit-fallthrough \
    -Wmissing-declarations \
    -Wshadow \
    -Wsign-compare \
    -Wstrict-prototypes
LDFLAGS ?=
LDLIBS ?=

EXTRA_CPPFLAGS ?=
EXTRA_CFLAGS ?=
EXTRA_LDFLAGS ?=
EXTRA_LDLIBS ?=

GIT_VERSION != test -d .git && command -v git >/dev/null 2>&1 && git describe --always --dirty || echo 3.1.3
VERSION ?= ${GIT_VERSION}

# Immutable flags
export BFS_CPPFLAGS= \
    -D__EXTENSIONS__ \
    -D_ATFILE_SOURCE \
    -D_BSD_SOURCE \
    -D_DARWIN_C_SOURCE \
    -D_DEFAULT_SOURCE \
    -D_GNU_SOURCE \
    -D_LARGEFILE64_SOURCE \
    -D_POSIX_PTHREAD_SEMANTICS \
    -D_FILE_OFFSET_BITS=64 \
    -D_TIME_BITS=64
export BFS_CFLAGS= -std=c17 -pthread

# Platform-specific system libraries
LDLIBS,DragonFly := -lposix1e
LDLIBS,Linux := -lrt
LDLIBS,NetBSD := -lutil
LDLIBS,SunOS := -lsocket -lnsl
_BFS_LDLIBS := ${LDLIBS,${OS}}
export BFS_LDLIBS=${_BFS_LDLIBS}

# Build profiles
ASAN ?= n
LSAN ?= n
MSAN ?= n
TSAN ?= n
UBSAN ?= n
GCOV ?= n
LINT ?= n
RELEASE ?= n

export ASAN_CFLAGS= -fsanitize=address
export LSAN_CFLAGS= -fsanitize=leak
export MSAN_CFLAGS= -fsanitize=memory -fsanitize-memory-track-origins
export UBSAN_CFLAGS= -fsanitize=undefined

# https://github.com/google/sanitizers/issues/342
export TSAN_CPPFLAGS= -DBFS_USE_TARGET_CLONES=0
export TSAN_CFLAGS= -fsanitize=thread

export SAN=${ASAN}${LSAN}${MSAN}${TSAN}${UBSAN}
export SAN_CFLAGS= -fno-sanitize-recover=all

# MSAN and TSAN both need all code to be instrumented
export NOLIBS= ${MSAN}${TSAN}

# gcov only intercepts fork()/exec() with -std=gnu*
export GCOV_CFLAGS= --coverage -std=gnu17

export LINT_CPPFLAGS= -D_FORTIFY_SOURCE=3 -DBFS_LINT
export LINT_CFLAGS= -Werror -O2

export RELEASE_CPPFLAGS= -DNDEBUG
export RELEASE_CFLAGS= -O3 -flto=auto

# Save the new value of these variables, before they potentially get overridden
# by `-include ${CONFIG}` below

_XPREFIX := ${PREFIX}
_XMANDIR := ${MANDIR}

_XOS := ${OS}
_XARCH := ${ARCH}

_XCC := ${CC}
_XINSTALL := ${INSTALL}
_XMKDIR := ${MKDIR}
_XRM := ${RM}

_XCPPFLAGS := ${CPPFLAGS}
_XCFLAGS := ${CFLAGS}
_XLDFLAGS := ${LDFLAGS}
_XLDLIBS := ${LDLIBS}

# GNU make supports `export VAR`, but BSD make requires `export VAR=value`.
# Sadly, GNU make gives a recursion error on `export VAR=${VAR}`.

_BUILDDIR := ${BUILDDIR}
_PKG_CONFIG := ${PKG_CONFIG}

export BUILDDIR=${_BUILDDIR}
export PKG_CONFIG=${_PKG_CONFIG}

export XPREFIX=${_XPREFIX}
export XMANDIR=${_XMANDIR}

export XOS=${_XOS}
export XARCH=${_XARCH}

export XCC=${_XCC}
export XINSTALL=${_XINSTALL}
export XMKDIR=${_XMKDIR}
export XRM=${_XRM}

export XCPPFLAGS=${_XCPPFLAGS}
export XCFLAGS=${_XCFLAGS}
export XLDFLAGS=${_XLDFLAGS}
export XLDLIBS=${_XLDLIBS}

# The configuration file generated by `make config`
CONFIG := ${GEN}/config.mk
-include ${CONFIG}

## Configuration phase (`make config`)

# Makefile fragments generated by `make config`
MKS := \
    ${GEN}/vars.mk \
    ${GEN}/deps.mk \
    ${GEN}/objs.mk \
    ${GEN}/pkgs.mk

# The configuration goal itself
config: ${MKS}
	@printf 'include $${GEN}/%s\n' ${.ALLSRC:${GEN}/%=%} >${CONFIG}
.PHONY: config

# Saves the configurable variables
${GEN}/vars.mk:
	@${XMKDIR} ${@D}
	@config/vars.sh >$@
	@cat $@
.PHONY: ${GEN}/vars.mk

# Check for dependency generation support
${GEN}/deps.mk: ${GEN}/vars.mk
	@+${MAKE} -rs -f config/deps.mk TARGET=$@
	@cat $@
	@printf -- '-include %s\n' ${OBJS:.o=.d} >>$@
.PHONY: ${GEN}/deps.mk

# Lists file.o: file.c dependencies
${GEN}/objs.mk:
	@${MKDIR} ${@D}
	@for obj in ${OBJS:${OBJ}/%.o=%}; do printf '$${OBJ}/%s.o: %s.c\n' "$$obj" "$$obj"; done >$@
.PHONY: ${GEN}/objs.mk

# External dependencies
PKG_MKS := \
    ${GEN}/libacl.mk \
    ${GEN}/libcap.mk \
    ${GEN}/libselinux.mk \
    ${GEN}/liburing.mk \
    ${GEN}/oniguruma.mk

# Auto-detect dependencies and their build flags
${GEN}/pkgs.mk: ${PKG_MKS}
	@printf 'include $${GEN}/%s\n' ${.ALLSRC:${GEN}/%=%} >$@
	@+${MAKE} -rs -f config/pkgs.mk TARGET=$@
	@grep -v '^include' $@ || :
.PHONY: ${GEN}/pkgs.mk

# Auto-detect dependencies
${PKG_MKS}: ${GEN}/vars.mk
	@+${MAKE} -rs -f config/pkg.mk TARGET=$@
	@cat $@
.PHONY: ${PKG_MKS}

# bfs used to have flag-like targets (`make release`, `make asan ubsan`, etc.).
# Direct users to the new configuration system.
asan lsan msan tsan ubsan gcov lint release::
	@printf 'error: `%s %s` is no longer supported. ' "${MAKE}" $@ >&2
	@printf 'Use `%s config %s=y` instead.\n' "${MAKE}" $$(echo $@ | tr '[a-z]' '[A-Z]') >&2
	@false

# Print an error if `make` is run before `make config`
${CONFIG}::
	@if ! [ -e $@ ]; then \
	    printf 'error: You must run `%s config` before `%s`.\n' "${MAKE}" "${MAKE}" >&2; \
	    false; \
	fi

## Build phase (`make`)

# The main binary
bfs: ${BIN}/bfs
.PHONY: bfs

# All binaries
BINS := \
    ${BIN}/bfs \
    ${BIN}/tests/mksock \
    ${BIN}/tests/units \
    ${BIN}/tests/xspawnee \
    ${BIN}/tests/xtouch

all: ${BINS}
.PHONY: all

# All object files except the entry point
LIBBFS := \
    ${OBJ}/src/alloc.o \
    ${OBJ}/src/bar.o \
    ${OBJ}/src/bfstd.o \
    ${OBJ}/src/bftw.o \
    ${OBJ}/src/color.o \
    ${OBJ}/src/ctx.o \
    ${OBJ}/src/diag.o \
    ${OBJ}/src/dir.o \
    ${OBJ}/src/dstring.o \
    ${OBJ}/src/eval.o \
    ${OBJ}/src/exec.o \
    ${OBJ}/src/expr.o \
    ${OBJ}/src/fsade.o \
    ${OBJ}/src/ioq.o \
    ${OBJ}/src/mtab.o \
    ${OBJ}/src/opt.o \
    ${OBJ}/src/parse.o \
    ${OBJ}/src/printf.o \
    ${OBJ}/src/pwcache.o \
    ${OBJ}/src/stat.o \
    ${OBJ}/src/thread.o \
    ${OBJ}/src/trie.o \
    ${OBJ}/src/typo.o \
    ${OBJ}/src/version.o \
    ${OBJ}/src/xregex.o \
    ${OBJ}/src/xspawn.o \
    ${OBJ}/src/xtime.o

# Group relevant flags together
ALL_CFLAGS = ${CPPFLAGS} ${CFLAGS} ${DEPFLAGS}
ALL_LDFLAGS = ${CFLAGS} ${LDFLAGS}

# The main binary
${BIN}/bfs: ${LIBBFS} ${OBJ}/src/main.o

${BINS}:
	@${MKDIR} ${@D}
	+${CC} ${ALL_LDFLAGS} ${.ALLSRC} ${LDLIBS} -o $@
	${POSTLINK}

# All object files
OBJS := \
    ${OBJ}/src/main.o \
    ${OBJ}/tests/alloc.o \
    ${OBJ}/tests/bfstd.o \
    ${OBJ}/tests/bit.o \
    ${OBJ}/tests/ioq.o \
    ${OBJ}/tests/main.o \
    ${OBJ}/tests/mksock.o \
    ${OBJ}/tests/trie.o \
    ${OBJ}/tests/xspawn.o \
    ${OBJ}/tests/xspawnee.o \
    ${OBJ}/tests/xtime.o \
    ${OBJ}/tests/xtouch.o \
    ${LIBBFS}

# Depend on ${CONFIG} to make sure `make config` runs first, and to rebuild when
# the configuration changes
${OBJS}: ${CONFIG}
	@${MKDIR} ${@D}
	${CC} ${ALL_CFLAGS} -c ${@:${OBJ}/%.o=%.c} -o $@

# Save the version number to this file, but only update VERSION if it changes
${GEN}/NEWVERSION::
	@${MKDIR} ${@D}
	@printf '%s\n' '${VERSION}' >$@

${GEN}/VERSION: ${GEN}/NEWVERSION
	@test -e $@ && cmp -s $@ ${.ALLSRC} && rm ${.ALLSRC} || mv ${.ALLSRC} $@

# Rebuild version.c whenever the version number changes
${OBJ}/src/version.o: ${GEN}/VERSION
${OBJ}/src/version.o: CPPFLAGS := ${CPPFLAGS} -DBFS_VERSION='"${VERSION}"'

# Clean all build products
clean::
	${RM} -r ${BIN} ${OBJ}

# Clean everything, including generated files
distclean: clean
	${RM} -r ${GEN}
.PHONY: distclean

## Test phase (`make check`)

# Unit test binaries
UTEST_BINS := \
    ${BIN}/tests/units \
    ${BIN}/tests/xspawnee

# Integration test binaries
ITEST_BINS := \
    ${BIN}/tests/mksock \
    ${BIN}/tests/xtouch

# Build (but don't run) test binaries
tests: ${UTEST_BINS} ${ITEST_BINS}
.PHONY: tests

# Run all the tests
check: unit-tests integration-tests
.PHONY: check

# Run the unit tests
unit-tests: ${UTEST_BINS}
	${BIN}/tests/units
.PHONY: unit-tests

${BIN}/tests/units: \
    ${OBJ}/tests/alloc.o \
    ${OBJ}/tests/bfstd.o \
    ${OBJ}/tests/bit.o \
    ${OBJ}/tests/ioq.o \
    ${OBJ}/tests/main.o \
    ${OBJ}/tests/trie.o \
    ${OBJ}/tests/xspawn.o \
    ${OBJ}/tests/xtime.o \
    ${LIBBFS}

${BIN}/tests/xspawnee: \
    ${OBJ}/tests/xspawnee.o

# The different flag combinations we check
INTEGRATIONS := default dfs ids eds j1 j2 j3 s
INTEGRATION_TESTS := ${INTEGRATIONS:%=check-%}

# Check just `bfs`
check-default: ${BIN}/bfs ${ITEST_BINS}
	+./tests/tests.sh --make="${MAKE}" --bfs="${BIN}/bfs" ${TEST_FLAGS}

# Check the different search strategies
check-dfs check-ids check-eds: ${BIN}/bfs ${ITEST_BINS}
	+./tests/tests.sh --make="${MAKE}" --bfs="${BIN}/bfs -S ${@:check-%=%}" ${TEST_FLAGS}

# Check various flags
check-j1 check-j2 check-j3 check-s: ${BIN}/bfs ${ITEST_BINS}
	+./tests/tests.sh --make="${MAKE}" --bfs="${BIN}/bfs -${@:check-%=%}" ${TEST_FLAGS}

# Run the integration tests
integration-tests: ${INTEGRATION_TESTS}
.PHONY: integration-tests

${BIN}/tests/mksock: \
    ${OBJ}/tests/mksock.o \
    ${LIBBFS}

${BIN}/tests/xtouch: \
    ${OBJ}/tests/xtouch.o \
    ${LIBBFS}

# `make distcheck` configurations
DISTCHECKS := distcheck-asan distcheck-tsan distcheck-release

# Don't use msan on macOS
IS_DARWIN,Darwin := y
IS_DARWIN := ${IS_DARWIN,${OS}}
DISTCHECK_MSAN, := distcheck-msan
DISTCHECKS += ${DISTCHECK_MSAN,${IS_DARWIN}}

# Only add a 32-bit build on 64-bit Linux
DISTCHECK_M32,Linux,x86_64 := distcheck-m32
DISTCHECKS += ${DISTCHECK_M32,${OS},${ARCH}}

# Test multiple configurations
distcheck: ${DISTCHECKS}
.PHONY: distcheck

# Per-distcheck configuration
DISTCHECK_CONFIG_asan := ASAN=y UBSAN=y
DISTCHECK_CONFIG_msan := MSAN=y UBSAN=y CC=clang
DISTCHECK_CONFIG_tsan := TSAN=y UBSAN=y CC=clang
DISTCHECK_CONFIG_m32 := EXTRA_CFLAGS="-m32" PKG_CONFIG_LIBDIR=/usr/lib32/pkgconfig
DISTCHECK_CONFIG_release := RELEASE=y

${DISTCHECKS}::
	+${MAKE} -rs BUILDDIR=${BUILDDIR}/$@ config ${DISTCHECK_CONFIG_${@:distcheck-%=%}}
	+${MAKE} -s BUILDDIR=${BUILDDIR}/$@ check TEST_FLAGS="--sudo --verbose=skipped"

## Packaging (`make install`)

DEST_PREFIX := ${DESTDIR}${PREFIX}
DEST_MANDIR := ${DESTDIR}${MANDIR}

install::
	${MKDIR} ${DEST_PREFIX}/bin
	${INSTALL} -m755 ${BIN}/bfs ${DEST_PREFIX}/bin/bfs
	${MKDIR} ${DEST_MANDIR}/man1
	${INSTALL} -m644 docs/bfs.1 ${DEST_MANDIR}/man1/bfs.1
	${MKDIR} ${DEST_PREFIX}/share/bash-completion/completions
	${INSTALL} -m644 completions/bfs.bash ${DEST_PREFIX}/share/bash-completion/completions/bfs
	${MKDIR} ${DEST_PREFIX}/share/zsh/site-functions
	${INSTALL} -m644 completions/bfs.zsh ${DEST_PREFIX}/share/zsh/site-functions/_bfs
	${MKDIR} ${DEST_PREFIX}/share/fish/vendor_completions.d
	${INSTALL} -m644 completions/bfs.fish ${DEST_PREFIX}/share/fish/vendor_completions.d/bfs.fish

uninstall::
	${RM} ${DEST_PREFIX}/share/bash-completion/completions/bfs
	${RM} ${DEST_PREFIX}/share/zsh/site-functions/_bfs
	${RM} ${DEST_PREFIX}/share/fish/vendor_completions.d/bfs.fish
	${RM} ${DEST_MANDIR}/man1/bfs.1
	${RM} ${DEST_PREFIX}/bin/bfs

# Check that `make install` works and `make uninstall` removes everything
check-install::
	+${MAKE} install DESTDIR=${BUILDDIR}/pkg
	+${MAKE} uninstall DESTDIR=${BUILDDIR}/pkg
	${BIN}/bfs ${BUILDDIR}/pkg -not -type d -print -exit 1
	${RM} -r ${BUILDDIR}/pkg
