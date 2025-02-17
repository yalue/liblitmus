# figure out what kind of host we are running on
host-arch := $(shell uname -m | \
	sed -e s/i.86/i386/ -e s/sun4u/sparc64/ -e s/arm.*/arm/)

# ##############################################################################
# User variables

# user variables can be specified in the environment or in a .config file
-include .config

# ARCH -- what architecture are we compiling for?
ARCH ?= ${host-arch}

# LITMUS_KERNEL -- where to find the litmus kernel?
LITMUS_KERNEL ?= ../linux


# ##############################################################################
# Internal configuration.

# compiler flags
flags-debug    = -O2 -Wall -Werror -g -Wdeclaration-after-statement
flags-api      = -D_XOPEN_SOURCE=600 -D_GNU_SOURCE

# architecture-specific flags
flags-i386     = -m32
flags-x86_64   = -m64
flags-sparc64  = -mcpu=v9 -m64
# default: none

# name of the directory that has the arch headers in the Linux source
include-i386     = x86
include-x86_64   = x86
include-sparc64  = sparc
# default: the arch name
include-${ARCH} ?= ${ARCH}

# by default we use the local version
LIBLITMUS ?= .

# where to find header files
headers =  -I${LIBLITMUS}/include -I${LIBLITMUS}/arch/${include-${ARCH}}/include
headers += -I${LIBLITMUS}/arch/${include-${ARCH}}/include/uapi
headers += -I${LIBLITMUS}/arch/${include-${ARCH}}/include/generated/uapi

# combine options
CPPFLAGS = ${flags-api} ${flags-${ARCH}} -DARCH=${ARCH} ${headers}
CFLAGS   = ${flags-debug} -fPIC
LDFLAGS  = ${flags-${ARCH}}

# how to link against liblitmus
liblitmus-flags = -L${LIBLITMUS} -llitmus

# Force gcc instead of cc, but let the user specify a more specific version if
# desired.
ifeq (${CC},cc)
CC = gcc
endif

# incorporate cross-compiler (if any)
CC  := ${CROSS_COMPILE}${CC}
LD  := ${CROSS_COMPILE}${LD}
AR  := ${CROSS_COMPILE}${AR}

# ##############################################################################
# Targets

all     = lib ${rt-apps}
rt-apps = cycles base_task rt_launch rtspin release_ts measure_syscall \
	  base_mt_task uncache runtests resctl

.PHONY: all lib clean dump-config TAGS tags cscope help doc

all: ${all} inc/config.makefile

# Write a distilled version of the flags for clients of the library. Ideally,
# this should depend on liblitmus.a, but that requires LIBLITMUS to be a
# private override. Private overrides are only supported starting with make
# 3.82, which is not yet in common use.
inc/config.makefile: LIBLITMUS = $${LIBLITMUS}
inc/config.makefile: Makefile
	@printf "%-15s= %-20s\n" \
		ARCH ${ARCH} \
		CFLAGS '${CFLAGS}' \
		LDFLAGS '${LDFLAGS}' \
		LDLIBS '${liblitmus-flags}' \
		CPPFLAGS '${CPPFLAGS}' \
		CC '${shell which ${CC}}' \
		LD '${shell which ${LD}}' \
		AR '${shell which ${AR}}' \
	> $@

dump-config:
	@echo Build configuration:
	@printf "%-15s= %-20s\n" \
		ARCH ${ARCH} \
		LITMUS_KERNEL "${LITMUS_KERNEL}" \
		CROSS_COMPILE "${CROSS_COMPILE}" \
		headers "${headers}" \
		"kernel headers" "${imported-headers}" \
		CFLAGS "${CFLAGS}" \
		LDFLAGS "${LDFLAGS}" \
		CPPFLAGS "${CPPFLAGS}" \
		CC "${CC}" \
		CPP "${CPP}" \
		LD "${LD}" \
		AR "${AR}" \
		obj-all "${obj-all}"

help:
	@cat INSTALL

doc:
	doxygen Doxyfile

clean:
	rm -f ${rt-apps}
	rm -f *.o *.d *.a test_catalog.inc
	rm -f ${imported-headers}
	rm -f inc/config.makefile
	rm -f tags TAGS cscope.files cscope.out
	rm -r -f docs

# Emacs Tags
TAGS:
	@echo TAGS
	@find . -type f -and  -iname '*.[ch]' | xargs etags

# Vim Tags
tags:
	@echo tags
	@find . -type f -and  -iname '*.[ch]' | xargs ctags

# cscope DB
cscope:
	@echo cscope
	@find . -type f -and  -iname '*.[ch]' | xargs printf "%s\n" > cscope.files
	@cscope -b

# ##############################################################################
# Kernel headers.
# The kernel does not like being #included directly, so let's
# copy out the parts that we need.

# Litmus headers
include/litmus/%.h: ${LITMUS_KERNEL}/include/litmus/%.h
	@mkdir -p ${dir $@}
	cp $< $@

# asm headers
arch/${include-${ARCH}}/include/uapi/asm/%.h: \
	${LITMUS_KERNEL}/arch/${include-${ARCH}}/include/uapi/asm/%.h
	@mkdir -p ${dir $@}
	cp $< $@

arch/${include-${ARCH}}/include/generated/uapi/asm/%.h: \
	${LITMUS_KERNEL}/arch/${include-${ARCH}}/include/generated/uapi/asm/%.h
	@mkdir -p ${dir $@}
	cp $< $@

litmus-headers = \
	include/litmus/rt_param.h \
	include/litmus/ctrlpage.h \
	include/litmus/fpmath.h

imported-headers = ${litmus-headers} 

# Let's not copy these twice.
.SECONDARY: ${imported-headers}

# ##############################################################################
# liblitmus

lib: liblitmus.a

# all .c file in src/ are linked into liblitmus
vpath %.c src/
obj-lib = $(patsubst src/%.c,%.o,$(wildcard src/*.c))

liblitmus.a: ${obj-lib}
	${AR} rcs $@ $+

# ##############################################################################
# Tests suite.

# tests are found in tests/
vpath %.c tests/

src-runtests = $(wildcard tests/*.c)
obj-runtests = $(patsubst tests/%.c,%.o,${src-runtests})
lib-runtests = -lrt

# generate list of tests automatically
test_catalog.inc: $(filter-out tests/runner.c,${src-runtests})
	@[ ! -z "$$(which python)" ] || \
		(echo '  [!!!] Error: Need to have python installed in PATH.'; exit 1)
	@tests/make_catalog.py $+ > $@ || \
		(rm $@; echo "  [!!!] Error: Could not generate test catalogue."; exit 1)

tests/runner.c: test_catalog.inc


# ##############################################################################
# Tools that link with liblitmus

# these source files are found in bin/
vpath %.c bin/

obj-cycles = cycles.o

obj-base_task = base_task.o

obj-base_mt_task = base_mt_task.o
ldf-base_mt_task = -pthread

obj-rt_launch = rt_launch.o common.o

obj-rtspin = rtspin.o common.o
lib-rtspin = -lrt

obj-uncache = uncache.o
lib-uncache = -lrt

obj-release_ts = release_ts.o common.o

obj-measure_syscall = null_call.o
lib-measure_syscall = -lm

obj-resctl = resctl.o


# ##############################################################################
# Build everything that depends on liblitmus.

.SECONDEXPANSION:
${rt-apps}: $${obj-$$@} liblitmus.a
	$(CC) -o $@ $(LDFLAGS) ${ldf-$@} $(filter-out liblitmus.a,$+) $(LOADLIBS) $(LDLIBS) ${liblitmus-flags} ${lib-$@}

# ##############################################################################
# Dependency resolution.

vpath %.c bin/ src/ tests/

obj-all = ${sort ${foreach target,${all},${obj-${target}}}}

# rule to generate dependency files
%.d: %.c ${imported-headers}
	@set -e; rm -f $@; \
		$(CC) -MM $(CPPFLAGS) $< > $@.$$$$; \
		sed 's,\($*\)\.o[ :]*,\1.o $@ : ,g' < $@.$$$$ > $@; \
		rm -f $@.$$$$

ifeq ($(MAKECMDGOALS),)
MAKECMDGOALS += all
endif

ifneq ($(filter-out dump-config clean help,$(MAKECMDGOALS)),)

# Pull in dependencies.
-include ${obj-all:.o=.d}

# Let's make sure the kernel header path is ok.
config-ok  := $(shell test -d "${LITMUS_KERNEL}" || echo invalid path. )
config-ok  += $(shell test -f "${LITMUS_KERNEL}/${word 1,${litmus-headers}}" \
	|| echo cannot find header. )
ifneq ($(strip $(config-ok)),)
$(info (!!) Could not find a LITMUS^RT kernel at ${LITMUS_KERNEL}: ${config-ok})
$(info (!!) Are you sure the path is correct?)
$(info (!!) Run 'make dump-config' to see the build configuration.)
$(info (!!) Edit the file .config to override the default configuration.)
$(error Cannot build without access to the LITMUS^RT kernel source)
endif

endif
