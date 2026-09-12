// Run against an isolated, deployed personal Rime Ice configuration.
// Build/run commands: docs/spacing/PENDING_URL.md. Never use live user data.
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
  const char *seq[] = {"d1",     "nihao,", "nihao . ", "nihao!", "nihao?",
                       "nihao;", "nihao:", "1,",       "1.",     "1:",
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

  const char *ellipsis[] = {"... ", "nihao ...{Return}", NULL};
  const char *ellipsis_text[] = {"...", "你好..."};
  for (int i = 0; ellipsis[i]; i++) {
    RimeSessionId s = session();
    assert(api->simulate_key_sequence(s, ellipsis[i]));
    check(s, ellipsis[i], ellipsis_text[i]);
    api->destroy_session(s);
  }

  // A dot extends the composition; it never selects the highlighted Chinese
  // candidate. Domain text must remain exact (including case/path) and unique.
  const char *urls[] = {
      "x.com",           "example.com", "EXample.com/Case?Q=Ab#Part",
      "https://x.com/A", "v2ray.com",   "abc-",
      "abc-def",         "abc-123",     "ABc-Def",
      "foo-bar.com",     "..",          "...",
      "......",          NULL};
  for (int i = 0; urls[i]; i++) {
    RimeSessionId s = session();
    for (const char *p = urls[i]; *p; p++) {
      assert(api->process_key(s, *p, 0));
      RIME_STRUCT(RimeCommit, premature);
      int committed = api->get_commit(s, &premature);
      checks++;
      if (committed) {
        printf("FAIL premature commit while typing %s: %s\n", urls[i],
               premature.text);
        failures++;
        api->free_commit(&premature);
      }
    }
    RIME_STRUCT(RimeContext, ctx);
    assert(api->get_context(s, &ctx));
    checks++;
    if (ctx.menu.num_candidates != 1 ||
        strcmp(ctx.menu.candidates[0].text, urls[i]) ||
        !ctx.menu.is_last_page || strcmp(ctx.composition.preedit, urls[i])) {
      printf("FAIL exact unique literal candidate: %s\n", urls[i]);
      failures++;
    }
    api->free_context(&ctx);
    assert(api->process_key(s, 0xff0d, 0));
    check(s, urls[i], urls[i]);
    api->destroy_session(s);
  }
  // A pinyin separator makes this a non-URL composition, but '.' must still
  // not force its Chinese candidate onto the document.
  {
    RimeSessionId s = session();
    assert(api->simulate_key_sequence(s, "ni'hao."));
    RIME_STRUCT(RimeCommit, c);
    int committed = api->get_commit(s, &c);
    checks++;
    if (committed) {
      puts("FAIL dot committed a non-URL composition");
      failures++;
      api->free_commit(&c);
    }
    assert(api->process_key(s, 0xff1b, 0)); // Escape cancels pending input.
    api->destroy_session(s);
  }

  {
    RimeSessionId s = session();
    assert(api->simulate_key_sequence(s, "x.c"));
    assert(api->process_key(s, 0xff08, 0));
    assert(
        api->process_key(s, 0xff08, 0)); // Remove c and dot, restoring pinyin.
    RIME_STRUCT(RimeContext, ctx);
    assert(api->get_context(s, &ctx));
    assert(ctx.composition.length && ctx.menu.num_candidates > 1);
    api->free_context(&ctx);
    assert(api->process_key(s, '.', 0));
    assert(api->process_key(s, 0xff1b, 0)); // Escape must not submit the URL.
    RIME_STRUCT(RimeCommit, c);
    assert(!api->get_commit(s, &c));
    RIME_STRUCT(RimeContext, after);
    assert(api->get_context(s, &after));
    assert(!after.composition.length);
    api->free_context(&after);
    checks += 2;
    api->destroy_session(s);
  }
  // Literal hyphens must not remove the dedicated candidate paging keys.
  {
    RimeSessionId s = session();
    assert(api->process_key(s, 'd', 0));
    for (int page = 1; page >= 0; page--) {
      assert(api->process_key(s, page ? 0xff56 : 0xff55, 0));
      RIME_STRUCT(RimeContext, ctx);
      assert(api->get_context(s, &ctx));
      assert(ctx.menu.page_no == page);
      api->free_context(&ctx);
      checks++;
    }
    api->destroy_session(s);
  }
  // Control-A / Control-B page candidates without committing or deleting input.
  {
    RimeSessionId s = session();
    assert(api->process_key(s, 'd', 0));
    const char *keys = "abbbaa";
    const int pages[] = {0, 1, 2, 3, 2, 1};
    for (int i = 0; keys[i]; i++) {
      int handled = api->process_key(s, keys[i], 4); // Control mask
      RIME_STRUCT(RimeContext, ctx);
      assert(api->get_context(s, &ctx));
      checks++;
      if (!handled || ctx.menu.page_no != pages[i] || !ctx.composition.length ||
          strcmp(api->get_input(s), "d")) {
        printf("FAIL Control-%c: handled %d, page %d, expected %d\n", keys[i],
               handled, ctx.menu.page_no, pages[i]);
        failures++;
      }
      api->free_context(&ctx);
      RIME_STRUCT(RimeCommit, c);
      if (api->get_commit(s, &c)) {
        printf("FAIL Control paging committed %s\n", c.text);
        failures++;
        api->free_commit(&c);
      }
    }
    api->clear_composition(s);
    for (const char *p = "ab"; *p; p++) {
      checks++;
      if (api->process_key(s, *p, 4)) {
        printf("FAIL Control-%c consumed without candidates\n", *p);
        failures++;
      }
    }
    api->destroy_session(s);
  }
  // Comma commits punctuation until paging starts. Paging stays active when
  // returning to page zero, then resets with the next composition.
  {
    RimeSessionId s = session();
    assert(api->process_key(s, 'd', 0));
    const char *keys = "...,,,,";
    const int pages[] = {1, 2, 3, 2, 1, 0, 0};
    for (int i = 0; keys[i]; i++) {
      assert(api->process_key(s, keys[i], 0));
      RIME_STRUCT(RimeContext, ctx);
      assert(api->get_context(s, &ctx));
      checks++;
      if (ctx.menu.page_no != pages[i] || !ctx.composition.length) {
        printf("FAIL punctuation paging step %d: page %d, expected %d\n", i,
               ctx.menu.page_no, pages[i]);
        failures++;
      }
      api->free_context(&ctx);
      RIME_STRUCT(RimeCommit, c);
      if (api->get_commit(s, &c)) {
        printf("FAIL paging committed %s\n", c.text);
        failures++;
        api->free_commit(&c);
      }
    }
    assert(api->process_key(s, '1', 0));
    check(s, "select after punctuation paging", "的");
    assert(api->simulate_key_sequence(s, "d,"));
    check(s, "comma after fresh composition", "的，");
    api->destroy_session(s);
  }
  api->finalize();
  printf("%d input behavior checks, %d failures\n", checks, failures);
  return failures ? 1 : 0;
}
