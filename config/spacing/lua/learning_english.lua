-- Query both the typed spelling and lowercase spelling so case-transformed
-- candidates can reuse learned lowercase codes without hiding uppercase acronyms.
local M = {}

function M.init(env)
  env.translator = Component.Translator(env.engine, '', 'table_translator@' .. env.name_space)
end

function M.func(input, segment, env)
  local original = env.translator:query(input, segment)
  if input == input:lower() then
    if original then
      for candidate in original:iter() do yield(candidate) end
    end
    return
  end
  local lowercase = env.translator:query(input:lower(), segment)
  local function iterator(translation)
    return coroutine.wrap(function()
      if translation then
        for candidate in translation:iter() do coroutine.yield(candidate) end
      end
    end)
  end
  local next_original, next_lowercase = iterator(original), iterator(lowercase)
  local a, b = next_original(), next_lowercase()
  while a or b do
    if a and (not b or a.quality >= b.quality) then
      yield(a)
      a = next_original()
    else
      -- Native table results are Phrase objects with a writable preedit.
      -- ShadowCandidate delegates preedit to its original and cannot set it.
      b.preedit = input
      yield(b)
      b = next_lowercase()
    end
  end
end

function M.fini(env)
  env.translator = nil
end

return M
