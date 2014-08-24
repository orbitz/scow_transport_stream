CAMLP4=

OCAMLDEP_OPTS=-package core,async,scow,comparelib.syntax -syntax camlp4o
OCAMLC_OPTS=$(OCAMLDEP_OPTS) -w '@f@p@u@s@40'
OCAMLOPT_OPTS=$(OCAMLDEP_OPTS)

LIB_MODULES=scow_transport_stream.ml scow_transport_stream_server.ml \
	scow_transport_stream_codec.ml
NON_LIB_MODULES=

BYTE_TARGETS=scow_transport_stream.cma
NATIVE_TARGETS=scow_transport_stream.cmxa

.PHONY: all test install

all: native-code byte-code

install: all
	ocamlfind install scow_transport_stream \
	META \
	$(BYTE_TARGETS) \
	$(NATIVE_TARGETS) \
	scow_transport_stream.a \
	*.cmx \
	*.cmi \
	*.mli

test:

# Dependencies
include ../Ocamlrules.mk.in
