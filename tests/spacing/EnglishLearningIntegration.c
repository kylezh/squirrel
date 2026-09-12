#include <assert.h>
#include <dlfcn.h>
#include <rime_api.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static RimeApi *api;
static RimeSessionId s;
static int rank(const char *code, const char *word) {
  api->clear_composition(s);
  assert(api->simulate_key_sequence(s, code));
  RimeCandidateListIterator it = {0};
  int index = 0, result = -1;
  if (api->candidate_list_begin(s, &it)) {
    while (index < 100 && api->candidate_list_next(&it)) {
      if (strcmp(it.candidate.text, word) == 0) {
        result = index;
        break;
      }
      index++;
    }
    api->candidate_list_end(&it);
  }
  return result;
}
int main(int argc, char **argv) {
  assert(argc == 4);
  char library[4096], plugin[4096];
  snprintf(library, sizeof(library), "%s/lib/librime.1.dylib", argv[1]);
  snprintf(plugin, sizeof(plugin), "%s/lib/rime-plugins/librime-lua.dylib",
           argv[1]);
  void *lib = dlopen(library, RTLD_NOW | RTLD_GLOBAL);
  assert(lib);
  assert(dlopen(plugin, RTLD_NOW | RTLD_GLOBAL));
  RimeApi *(*get_api)(void) = dlsym(lib, "rime_get_api");
  api = get_api();
  RIME_STRUCT(RimeTraits, t);
  t.shared_data_dir = argv[3];
  t.user_data_dir = argv[3];
  t.app_name = "rime.learningcheck";
  t.min_log_level = 2;
  const char *mods[] = {"default", "levers", "lua", NULL};
  t.modules = mods;
  api->setup(&t);
  api->initialize(&t);
  s = api->create_session();
  assert(s);
  assert(api->select_schema(s, "spacing_test_english"));
  api->set_option(s, "ascii_mode", 0);
  int before = rank("PY", "PYRAMID");
  printf("Before rank: %d\n", before + 1);
  assert(before >= 0);
  if (strcmp(argv[2], "train") == 0) {
    assert(before > 0);
    for (int i = 0; i < 20; i++) {
      int n = rank("PY", "PYRAMID");
      assert(n >= 0);
      assert(api->select_candidate(s, n));
      RIME_STRUCT(RimeCommit, c);
      assert(api->get_commit(s, &c));
      assert(strcmp(c.text, "PYRAMID") == 0);
      api->free_commit(&c);
    }
  }
  int after = rank("PY", "PYRAMID");
  printf("After rank: %d\n", after + 1);
  RIME_STRUCT(RimeContext, context);
  assert(api->get_context(s, &context));
  assert(strcmp(context.composition.preedit, "PY") == 0);
  api->free_context(&context);
  assert(api->process_key(s, 0xff0d, 4)); // Control+Return commits script text.
  RIME_STRUCT(RimeCommit, script);
  assert(api->get_commit(s, &script));
  assert(strcmp(script.text, "PY") == 0);
  api->free_commit(&script);
  assert(rank("AI", "AI") >= 0);
  api->clear_composition(s);
  api->destroy_session(s);
  api->finalize();
  if (after != 0) {
    puts("FAIL learned preference");
    return 1;
  }
  puts("PASS learned preference");
  return 0;
}
