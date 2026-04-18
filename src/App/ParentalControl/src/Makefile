# ============================================================
# gp_keypad — Makefile for Miyoo Mini / Onion OS
# ============================================================
# Build with the union-miyoomini-toolchain docker image:
#
#   docker run --rm -v $(pwd):/root/workspace \
#       miyoomini-toolchain make -C /root/workspace/src
#
# Or natively on Linux with the miyoomini toolchain installed:
#   make
# ============================================================

TARGET  = ../bin/gp_keypad

# Default to the miyoomini cross-compiler prefix if not overridden
CROSS_COMPILE ?= arm-linux-gnueabihf-
CC      = $(CROSS_COMPILE)gcc
STRIP   = $(CROSS_COMPILE)strip
CFLAGS  += -O2 -Wall
LDFLAGS += -lSDL -lSDL_ttf

# Header/lib search paths as provided by the union toolchain
SYSROOT ?= /opt/miyoomini-toolchain/arm-linux-gnueabihf/libc/usr
CFLAGS  += -I$(SYSROOT)/include -I$(SYSROOT)/include/SDL
LDFLAGS += -L$(SYSROOT)/lib

SRC = gp_keypad.c

all: $(TARGET)

$(TARGET): $(SRC)
	mkdir -p ../bin
	$(CC) $(CFLAGS) $(SRC) -o $@ $(LDFLAGS)
	$(STRIP) $@ || true

clean:
	rm -f $(TARGET)

.PHONY: all clean
