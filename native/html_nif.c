#include <stdlib.h>
#include <string.h>
#include <erl_nif.h>
#include "nokogiri_gumbo.h"

static ERL_NIF_TERM atom_comment, atom_error;

static ERL_NIF_TERM text(ErlNifEnv *env, const char *prefix, const char *s) {
  size_t prefix_size = strlen(prefix), size = strlen(s);
  ERL_NIF_TERM term;
  unsigned char *data = enif_make_new_binary(env, prefix_size + size, &term);
  memcpy(data, prefix, prefix_size);
  memcpy(data + prefix_size, s, size);
  return term;
}

static ERL_NIF_TERM children(ErlNifEnv *, const GumboVector *);

static const char *attribute_prefix(const GumboAttribute *attribute) {
  switch (attribute->attr_namespace) {
    case GUMBO_ATTR_NAMESPACE_XLINK: return "xlink:";
    case GUMBO_ATTR_NAMESPACE_XML: return "xml:";
    case GUMBO_ATTR_NAMESPACE_XMLNS: return strcmp(attribute->name, "xmlns") ? "xmlns:" : "";
    default: return "";
  }
}

static ERL_NIF_TERM node(ErlNifEnv *env, const GumboNode *gumbo_node) {
  if (gumbo_node->type == GUMBO_NODE_ELEMENT || gumbo_node->type == GUMBO_NODE_TEMPLATE) {
    const GumboVector *source = &gumbo_node->v.element.attributes;
    ERL_NIF_TERM *attributes = enif_alloc(sizeof(ERL_NIF_TERM) * (source->length ? source->length : 1));
    for (unsigned i = 0; i < source->length; i++) {
      const GumboAttribute *attribute = source->data[i];
      attributes[i] = enif_make_tuple2(env, text(env, attribute_prefix(attribute), attribute->name), text(env, "", attribute->value));
    }
    ERL_NIF_TERM list = enif_make_list_from_array(env, attributes, source->length);
    enif_free(attributes);
    return enif_make_tuple3(env, text(env, "", gumbo_node->v.element.name), list, children(env, &gumbo_node->v.element.children));
  }
  if (gumbo_node->type == GUMBO_NODE_COMMENT) return enif_make_tuple2(env, atom_comment, text(env, "", gumbo_node->v.text.text));
  return text(env, "", gumbo_node->v.text.text);
}

static ERL_NIF_TERM children(ErlNifEnv *env, const GumboVector *source) {
  ERL_NIF_TERM *nodes = enif_alloc(sizeof(ERL_NIF_TERM) * (source->length ? source->length : 1));
  for (unsigned i = 0; i < source->length; i++) nodes[i] = node(env, source->data[i]);
  ERL_NIF_TERM list = enif_make_list_from_array(env, nodes, source->length);
  enif_free(nodes);
  return list;
}

static ERL_NIF_TERM parse(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifBinary html;
  if (argc != 1 || !enif_inspect_binary(env, argv[0], &html)) return enif_make_badarg(env);

  char *input = enif_alloc(html.size + 1);
  if (!input) return enif_raise_exception(env, enif_make_atom(env, "enomem"));
  memcpy(input, html.data, html.size);
  input[html.size] = 0;

  GumboOptions options = kGumboDefaultOptions;
  options.fragment_context = "body";
  options.max_tree_depth = 401;
  options.max_attributes = 400;
  options.max_nodes = 10000;
  options.max_errors = 0;
  GumboOutput *output = gumbo_parse_with_options(&options, input, html.size);

  ERL_NIF_TERM result = output->status == GUMBO_STATUS_OK
    ? children(env, &output->root->v.element.children)
    : enif_make_tuple2(env, atom_error, text(env, "", gumbo_status_to_string(output->status)));

  gumbo_destroy_output(output);
  enif_free(input);
  return result;
}

static int load(ErlNifEnv *env, void **priv, ERL_NIF_TERM info) {
  atom_comment = enif_make_atom(env, "comment");
  atom_error = enif_make_atom(env, "error");
  return 0;
}

static ErlNifFunc functions[] = {
  {"parse_dirty", 1, parse, ERL_NIF_DIRTY_JOB_CPU_BOUND}
};

ERL_NIF_INIT(Elixir.Campfire.HtmlParser, functions, load, NULL, NULL, NULL)
