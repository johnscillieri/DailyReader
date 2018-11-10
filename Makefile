SOURCES = \
	daily_reader.nim

BIN_NAME = daily_reader
RELEASE_BIN = $(addsuffix _release,$(BIN_NAME))
DEBUG_BIN = $(addsuffix _debug,$(BIN_NAME))

UPX := $(shell command -v upx 2> /dev/null)

SHARED_FLAGS = \
	--cc: clang \
	--define: ssl
	# --dynlibOverrideAll \
    # --passL: "-static" \
    # --passL: "-lssl" \
	# --passL: "-lcrypto"

RELEASE_FLAGS = \
	--define: release \
	--nimcache: nimcache_release \
	--opt: speed \
	--passL: -O4 \
	--passL: -s \
	--deadCodeElim: on \
	--lineTrace: off \
	--stackTrace: off \
	--checks: off

DEBUG_FLAGS = \
	--define: debug \
	--nimcache: nimcache_debug \
	--deadCodeElim: on \
	--debuginfo \
	--debugger: native \
	--linedir: on \
	--stacktrace: on \
	--linetrace: on \
	--verbosity: 1

all: release debug package

release: ./bin/$(RELEASE_BIN)

debug: ./bin/$(DEBUG_BIN)

package: ./bin/$(BIN_NAME)

./bin/$(RELEASE_BIN): $(SOURCES)
	nim $(SHARED_FLAGS) $(RELEASE_FLAGS) --out:$(RELEASE_BIN) c $(BIN_NAME) && \
	mkdir -p bin && \
	mv $(RELEASE_BIN) bin

./bin/$(DEBUG_BIN): $(SOURCES)
	nim $(SHARED_FLAGS) $(DEBUG_FLAGS) --out:$(DEBUG_BIN) c $(BIN_NAME) && \
	mkdir -p bin && \
	mv $(DEBUG_BIN) bin && \
	rm -rf $(DEBUG_BIN).ndb

./bin/$(BIN_NAME): ./bin/$(RELEASE_BIN)
	cp ./bin/$(RELEASE_BIN) ./bin/$(BIN_NAME)
ifdef UPX
	upx --ultra-brute ./bin/$(BIN_NAME)
else
	@echo "\nUPX not found so binary isn't packed, only stripped.\n"
endif
	ls -lh ./bin

clean:
	rm -rf ./bin/*
	rm -rf ./nimcache_*
