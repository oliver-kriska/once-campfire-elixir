# Builds the Gumbo HTML parser NIF into priv/native (invoked by elixir_make).
ERTS_INCLUDE_DIR ?= $(shell erl -noshell -eval 'io:format("~ts/erts-~ts/include", [code:root_dir(), erlang:system_info(version)]), halt().')
PRIV := $(MIX_APP_PATH)/priv/native
NIF := $(PRIV)/campfire_html.so
HTML := $(PRIV)/campfire-html
PLATFORM := $(shell erl -noshell -eval 'io:format("~ts-~ts", [erlang:system_info(otp_release), erlang:system_info(system_architecture)]), halt().')
BUILD_DIR := $(abspath $(MIX_APP_PATH)/../../native/$(PLATFORM))
ARTIFACT := $(BUILD_DIR)/campfire_html.so
HTML_ARTIFACT := $(BUILD_DIR)/campfire-html
GUMBO := $(wildcard vendor/gumbo/src/*.c)

CFLAGS += -O2 -std=c99 -fPIC -I$(ERTS_INCLUDE_DIR) -Ivendor/gumbo/src
ifeq ($(shell uname -s),Darwin)
  LDFLAGS += -dynamiclib -undefined dynamic_lookup
else
  LDFLAGS += -shared
endif

all: $(ARTIFACT) $(HTML_ARTIFACT)
	@mkdir -p $(PRIV)
	@tmp="$(NIF).tmp.$$$$"; \
		cp $(ARTIFACT) "$$tmp" && mv -f "$$tmp" $(NIF) || \
		{ status=$$?; rm -f "$$tmp"; exit $$status; }
	@tmp="$(HTML).tmp.$$$$"; \
		cp $(HTML_ARTIFACT) "$$tmp" && mv -f "$$tmp" $(HTML) || \
		{ status=$$?; rm -f "$$tmp"; exit $$status; }

$(ARTIFACT): html_nif.c $(GUMBO) $(wildcard vendor/gumbo/src/*.h)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) html_nif.c $(GUMBO) $(LDFLAGS) -o $@

$(HTML_ARTIFACT): html.c $(GUMBO) $(wildcard vendor/gumbo/src/*.h)
	@mkdir -p $(BUILD_DIR)
	$(CC) -O2 -std=c99 -Ivendor/gumbo/src html.c $(GUMBO) -o $@

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(NIF)
	rm -f $(HTML)

.PHONY: all clean
