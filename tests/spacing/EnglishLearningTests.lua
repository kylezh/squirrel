-- Standalone tests for preserving candidate identity and combining case lookups.
local output = {}
function yield(candidate) output[#output + 1] = candidate end
function Candidate() error('A plain candidate would discard learning identity') end
function ShadowCandidate(original, kind, text, comment)
  return setmetatable({ type = kind, text = text, comment = comment,
    genuine = original.genuine or original }, { __index = original, __newindex = function(t, key, value)
      assert(key ~= 'preedit', 'Native ShadowCandidate preedit is read-only')
      rawset(t, key, value)
    end })
end
local function translation(items)
  if not items then return nil end
  return { iter = function()
    local state = { items = items, index = 0 }
    return function(actual)
      assert(actual == state, 'Translation iterator state must be preserved')
      actual.index = actual.index + 1
      return actual.items[actual.index]
    end, state
  end }
end
local autocap = dofile('config/spacing/lua/learning_autocap_filter.lua')
local candidate = {type='completion', text='pyramid', comment='test', quality=8, start=4, _end=6}
autocap(translation({candidate}), {engine={context={input='PY'}}})
assert(#output == 1 and output[1].text == 'PYRAMID')
assert(output[1].genuine == candidate and output[1].quality == 8)
assert(output[1].start == 4 and output[1]._end == 6)
output = {}
autocap(translation({candidate}), {engine={context={input='Py'}}})
assert(output[1].text == 'Pyramid' and output[1].genuine == candidate)
output = {}
autocap(translation({candidate}), {engine={context={input='py'}}})
assert(output[1] == candidate)

local queries, result_sets = {}, {}
Component = { Translator = function(engine, namespace, name)
  assert(name == 'table_translator@melt_eng')
  return { query = function(_, input, segment)
    assert(segment == 'segment')
    queries[#queries + 1] = input
    return translation(result_sets[input])
  end }
end }
local translator = dofile('config/spacing/lua/learning_english.lua')
local env = {name_space='melt_eng', engine={}}
translator.init(env)
local exact = {text='AI', quality=9}
local learned = {text='air', quality=10}
local other = {text='airplane', quality=4}
result_sets = {AI={exact}, ai={learned, other}}
output = {}
translator.func('AI', 'segment', env)
assert(#output == 3 and output[1] == learned and output[2] == exact and output[3] == other)
assert(queries[1] == 'AI' and queries[2] == 'ai')
assert(output[1].preedit == 'AI' and output[3].preedit == 'AI')
queries, output = {}, {}
translator.func('ai', 'segment', env)
assert(#queries == 1 and #output == 2 and output[1] == learned)
result_sets, output = {CPU={exact}}, {}
translator.func('CPU', 'segment', env)
assert(#output == 1 and output[1] == exact)
result_sets, output = {abc={learned}}, {}
translator.func('ABC', 'segment', env)
assert(#output == 1 and output[1] == learned and output[1].preedit == 'ABC')
result_sets, output = {}, {}
translator.func('NONE', 'segment', env)
assert(#output == 0)
translator.fini(env)
assert(env.translator == nil)
print('PASS: English case lookup, acronym fallback, iterator protocol, and learning identity')
