package.path = './config/spacing/lua/?.lua;' .. package.path
local module = require('mixed_spacing')
local function notifier()
  return {connect = function(self, fn) self.callback = fn; return {disconnect = function() self.callback = nil end} end}
end
local function setup(property)
  local ctx = {commit_notifier=notifier(),unhandled_key_notifier=notifier(),property_update_notifier=notifier(),property=property}
  function ctx:get_property(name) if name == 'squirrel_spacing_receipt' then return self.receipt or '' end; return self.property or '' end
  function ctx:set_property(name, value) self.receipt=value; if self.property_update_notifier.callback then self.property_update_notifier.callback(self,name) end end
  function ctx:get_commit_text() return self.text end
  local out = ''
  local env = {engine={context=ctx,commit_text=function(_,t) out=out..t end}}
  module.init(env)
  local function commit(text) ctx.text=text;ctx.commit_notifier.callback(ctx);out=out..text end
  local function update(value) ctx.property=value;ctx.property_update_notifier.callback(ctx,'squirrel_spacing_context') end
  return env,commit,update,function() return out end
end
local env,commit,update,result = setup(nil)
commit('中文');commit('hello');assert(result()=='中文hello','missing handshake must disable spacing')
module.fini(env)
env,commit,update,result = setup('1|test-session|1|empty')
commit('中文');commit('hello');assert(result()=='中文 hello','normal mixed commit')
update('1|test-session|2|empty');commit('中文');assert(result()=='中文 hello中文','epoch reset')
update('1|test-session|2|tracking');commit('hello');assert(result()=='中文 hello中文 hello')
update('1|test-session|1|tracking');commit('中文');assert(result()=='中文 hello中文 hello 中文','stale epoch ignored')
update('1|test-session|3|suspended');commit('hello');commit('中文')
assert(result()=='中文 hello中文 hello 中文hello中文','suspended commits cannot rearm')
update('1|test-session|4|uncertain');commit('hello');commit('中文')
assert(result():sub(-#'hello中文')=='hello中文')
update('broken');commit('hello');commit('中文');assert(result():sub(-#'hello中文')=='hello中文')
update('1|new-session|0|empty');commit('hello');assert(result():sub(-#'中文hello')=='中文hello')
module.fini(env)
print('PASS: Lua handshake, epoch resets, stale events, suspension, malformed protocol, session isolation')

for digit = 0, 9 do
  env,commit,update,result = setup('1|digits|1|empty')
  commit('中文');commit(tostring(digit));commit('中文')
  assert(result() == '中文 ' .. digit .. ' 中文', 'Han/digit boundaries: ' .. digit)
  module.fini(env)
end
env,commit,update,result = setup('1|digits|1|empty')
commit('A');commit('100');commit('中文');commit('3');commit('.');commit('14');commit('中文')
assert(result() == 'A100 中文 3.14 中文', 'alphanumeric runs and decimals stay intact')
update('1|digits|2|empty');commit('123')
assert(result():sub(-#'中文123') == '中文123', 'numeric boundary resets with context')
module.fini(env)
print('PASS: digits, decimals, alphanumeric runs and numeric context reset')
