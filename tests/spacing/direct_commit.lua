return {func = function(key, env)
  if not key:release() and key.keycode == 91 then
    env.engine:commit_text('中文')
    return 1
  end
  return 2
end}
