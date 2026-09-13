-- Space between consecutive Han and ASCII-alphanumeric commits in the same context.
-- No document inspection: reset whenever the caret position becomes uncertain.
local M = {}
local function kind(cp)
  if not cp then return nil end
  if (cp >= 48 and cp <= 57) or (cp >= 65 and cp <= 90)
    or (cp >= 97 and cp <= 122) then return 'en' end
  if (cp >= 0x3400 and cp <= 0x4DBF) or (cp >= 0x4E00 and cp <= 0x9FFF)
    or (cp >= 0xF900 and cp <= 0xFAFF) or (cp >= 0x20000 and cp <= 0x323AF) then
    return 'zh'
  end
  return nil
end
local function receipt(text, env)
  if not env.session then return end
  for i = 1, #text do env.hash = ((env.hash ~ text:byte(i)) * 16777619) & 0xFFFFFFFF end
  env.bytes = env.bytes + #text
  env.engine.context:set_property('squirrel_spacing_receipt',
    ('1|%s|%d|%d|%d'):format(env.session, env.epoch, env.bytes, env.hash))
end
local function record(text, env, passthrough)
  if text == '' then return end
  if env.allowed then
    local first = kind(utf8.codepoint(text))
    if first and env.last and first ~= env.last then
      receipt(' ', env)
      env.engine:commit_text(' ')
      -- Rime records an unhandled key before notifying us. The prefix space
      -- becomes the latest history record, although the client receives the
      -- key after that space. Restore that order for native numeric punctuation.
      if passthrough then env.engine.context.commit_history:push('thru', text) end
    end
    env.last = kind(utf8.codepoint(text, utf8.offset(text, -1)))
  end
  if not passthrough then receipt(text, env) end
end
local function update_context(ctx, env)
  local value = ctx:get_property('squirrel_spacing_context') or ''
  local version, session, epoch, state = value:match('^(%d+)|([%w%-]+)|(%d+)|([%a_]+)$')
  epoch = tonumber(epoch)
  if version ~= '1' or not epoch or
      not ({empty=true, tracking=true, suspended=true, uncertain=true})[state] then
    env.last, env.allowed = nil, false
    return
  end
  if session == env.session and env.epoch and epoch < env.epoch then return end
  if session ~= env.session or epoch ~= env.epoch then
    env.last, env.bytes, env.hash = nil, 0, 2166136261
  end
  env.session, env.epoch = session, epoch
  env.allowed = state == 'empty' or state == 'tracking'
  if not env.allowed then env.last = nil end
end

function M.init(env)
  env.last, env.bytes, env.hash = nil, 0, 2166136261
  update_context(env.engine.context, env)
  env.property_connection = env.engine.context.property_update_notifier:connect(function(ctx, name)
    if name == 'squirrel_spacing_context' then update_context(ctx, env) end
    if name == 'squirrel_spacing_receipt' and ctx:get_property(name) == '' then
      env.bytes, env.hash = 0, 2166136261
    end
  end)
  -- Grouped callbacks run before the engine's ungrouped commit callback.
  -- The candidate and dictionary learning remain untouched.
  env.commit_connection = env.engine.context.commit_notifier:connect(function(ctx)
    record(ctx:get_commit_text(), env)
  end, 0)
  env.unhandled_connection = env.engine.context.unhandled_key_notifier:connect(function(_, key)
    if key:release() then return end
    if key:ctrl() or key:alt() or key:super() then return end
    local code = key.keycode
    if code >= 32 and code <= 126 then
      record(string.char(code), env, true)
    elseif code < 0xFFE1 or code > 0xFFEE then
      env.last = nil
    end
  end)
end
function M.func(_, _env)
  -- The frontend distinguishes editing the document from editing a composition.
  return 2
end
function M.fini(env)
  if env.property_connection then env.property_connection:disconnect() end
  if env.commit_connection then env.commit_connection:disconnect() end
  if env.unhandled_connection then env.unhandled_connection:disconnect() end
end
return M
