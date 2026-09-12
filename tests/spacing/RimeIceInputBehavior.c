// Run against an isolated, deployed copy of the personal Rime Ice
// configuration. cc -I librime/src tests/spacing/RimeIceInputBehavior.c -o
// build/spacing/input-behavior build/spacing/input-behavior "$PWD"
// /path/to/isolated/user-data
#include <assert.h>
#include <dlfcn.h>
#include <rime_api.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static RimeApi *api;
static int checks, failures;
static RimeSessionId session(void) {
  RimeSessionId s = api->create_session();
  assert(s && api->select_schema(s, "rime_ice"));
  api->set_option(s, "ascii_mode", 0);
  api->set_option(s, "ascii_punct", 0);
  api->set_option(s, "full_shape", 0);
  return s;
}
static void check(RimeSessionId s, const char *label, const char *expected) {
  RIME_STRUCT(RimeCommit, c);
  int committed = api->get_commit(s, &c);
  RIME_STRUCT(RimeContext, ctx);
  assert(api->get_context(s, &ctx));
  int ok = committed && !strcmp(c.text, expected) && !ctx.composition.length;
  checks++;
  if (!ok) {
    failures++;
    printf("FAIL %s: expected %s, committed %s, preedit %s\n", label, expected,
           committed ? c.text : "<none>",
           ctx.composition.preedit ? ctx.composition.preedit : "");
  }
  if (committed)
    api->free_commit(&c);
  api->free_context(&ctx);
}
int main(int argc, char **argv) {
  assert(argc == 3);
  char path[4096];
  snprintf(path, sizeof(path), "%s/lib/librime.1.dylib", argv[1]);
  void *lib = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
  assert(lib);
  snprintf(path, sizeof(path), "%s/lib/rime-plugins/librime-lua.dylib",
           argv[1]);
  assert(dlopen(path, RTLD_NOW | RTLD_GLOBAL));
  RimeApi *(*get_api)(void) = dlsym(lib, "rime_get_api");
  api = get_api();
  RIME_STRUCT(RimeTraits, t);
  t.shared_data_dir = argv[2];
  t.user_data_dir = argv[2];
  t.app_name = "rime.inputbehavior";
  t.min_log_level = 2;
  const char *modules[] = {"default", "levers", "lua", NULL};
  t.modules = modules;
  api->setup(&t);
  api->initialize(&t);
  // 'v' is Rime Ice's explicit symbol prefix. k8 is a curated term prefix;
  // the configured seven-candidate page has no eighth candidate to select.
  for (char letter = 'a'; letter <= 'z'; letter++) {
    if (letter == 'v')
      continue;
    for (int digit = 1; digit <= 7; digit++) {
      RimeSessionId s = session();
      assert(api->process_key(s, letter, 0));
      RIME_STRUCT(RimeContext, ctx);
      assert(api->get_context(s, &ctx));
      assert(ctx.menu.num_candidates >= digit);
      char *expected = strdup(ctx.menu.candidates[digit - 1].text);
      api->free_context(&ctx);
      api->process_key(s, '0' + digit, 0);
      char label[] = {letter, (char)('0' + digit), 0};
      check(s, label, expected);
      free(expected);
      api->destroy_session(s);
    }
  }
  const char *seq[] = {"d1",     "nihao,", "nihao.", "nihao!", "nihao?",
                       "nihao;", "nihao:", "1,",     "1.",     "1:",
                       "k8s,",   "v2ray,", NULL};
  const char *expected[] = {"的",     "你好，", "你好。", "你好！",
                            "你好？", "你好；", "你好：", ",",
                            ".",      ":",      "K8s，",  "v2ray，"};
  for (int i = 0; seq[i]; i++) {
    RimeSessionId s = session();
    // Digit passthrough is delivered by the client; only the punctuation is
    // committed by Rime. simulate_key_sequence retains all Rime commit text.
    assert(api->simulate_key_sequence(s, seq[i]));
    check(s, seq[i], expected[i]);
    api->destroy_session(s);
  }
  api->finalize();
  printf("%d input behavior checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
