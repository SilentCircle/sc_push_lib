.PHONY: compile ct ct_clean dialyzer docclean distclean docs run xref clean info

REBAR_PROFILE ?= default
THIS_MAKEFILE := $(lastword $(MAKEFILE_LIST))

$(info $(THIS_MAKEFILE) is using REBAR_PROFILE=$(REBAR_PROFILE))

REBAR3_URL = https://s3.amazonaws.com/rebar3/rebar3
ERLANG_VER=$(shell erl -noinput -eval 'io:put_chars(erlang:system_info(system_version)),halt().')

# If there is a rebar in the current directory, use it
ifeq ($(wildcard rebar3),rebar3)
REBAR = $(CURDIR)/rebar3
endif

# Fallback to rebar on PATH
REBAR ?= $(shell which rebar3)

# And finally, prep to download rebar if all else fails
ifeq ($(REBAR),)
REBAR = $(CURDIR)/rebar3
endif

all: compile

info:
	@echo 'Erlang/OTP system version: $(ERLANG_VER)'
	@echo '$(REBAR_VSN)'

compile: $(REBAR)
	$(REBAR) do clean, compile

run: compile
	$(REBAR) shell --name sc_push_lib --setcookie scpf

clean: $(REBAR) docclean
	$(REBAR) clean

ct: $(REBAR)
	REBAR_DIR=$(CURDIR) $(REBAR) do clean, ct --readable

ct_clean:
	@rm -rf _build/test/logs/
	@rm -rf _build/test/cover/

dialyzer: $(REBAR)
	$(REBAR) dialyzer

docclean:
	@rm -rf doc/*.html doc/edoc-info html/

distclean: clean
	@rm -rf _build log logs .test sasl_error.log
	@rm -rf doc/*.html doc/edoc-info html/
	@rm -rf Mnesia.*/

docs: $(REBAR)
	$(REBAR) edoc

stashdoc: $(REBAR)
	EDOWN_TARGET=stash EDOWN_TOP_LEVEL_README_URL=$(README_URL) $(REBAR) docs

xref: $(REBAR)
	$(REBAR) xref

$(REBAR):
	curl -s -Lo rebar3 $(REBAR3_URL) || wget $(REBAR3_URL)
	chmod a+x $(REBAR)

# ex: ts=4 sts=4 sw=4 noet
