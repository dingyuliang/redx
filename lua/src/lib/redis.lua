local M = { }
M.connect = function(self)
  local redis = require("resty.redis")
  local red = redis:new()
  red:set_timeout(config.redis_timeout)
  local ok, err = red:connect(config.redis_host, config.redis_port)
  if not (ok) then
    library:log_err("Error connecting to redis: " .. err)
    self.msg = "error connectiong: " .. err
    self.status = 500
  else
    library.log("Connected to redis")
    if type(config.redis_password) == 'string' and #config.redis_password > 0 then
      library.log("Authenticated with redis")
      red:auth(config.redis_password)
    end
    return red
  end
end
M.finish = function(red)
  if config.redis_keepalive_pool_size == 0 then
    local ok, err = red:close()
  else
    local ok, err = red:set_keepalive(config.redis_keepalive_max_idle_timeout, config.redis_keepalive_pool_size)
    if not (ok) then
      library.log_err("failed to set keepalive: ", err)
      return 
    end
  end
end
M.test = function(self)
  local red = M.connect(self)
  local rand_value = tostring(math.random())
  local key = "healthcheck:" .. rand_value
  local ok, err = red:set(key, rand_value)
  if not (ok) then
    self.status = 500
    self.msg = "Failed to write to redis"
  end
  ok, err = red:get(key)
  if not (ok) then
    self.status = 500
    self.msg = "Failed to read redis"
  end
  if not (ok == rand_value) then
    self.status = 500
    self.msg = "Healthcheck failed to write and read from redis"
  end
  ok, err = red:del(key)
  if ok then
    self.status = 200
    self.msg = "OK"
  else
    self.status = 500
    self.msg = "Failed to delete key from redis"
  end
  return M.finish(red)
end
M.commit = function(self, red, error_msg)
  local results, err = red:commit_pipeline()
  if not results then
    library.log_err(error_msg .. err)
    self.msg = error_msg .. err
    self.status = 500
  else
    self.msg = "OK"
    self.status = 200
  end
end
M.flush = function(self)
  local red = M.connect(self)
  if red == nil then
    return nil
  end
  local ok, err = red:flushdb()
  if ok then
    self.status = 200
    self.msg = "OK"
  else
    self.status = 500
    self.msg = err
    library.log_err(err)
  end
  return M.finish(red)
end
M.get_data = function(self, asset_type, asset_name)
  local red = M.connect(self)
  if red == nil then
    return nil
  end
  local _exp_0 = asset_type
  if 'frontends' == _exp_0 then
    self.resp, self.msg = red:get('frontend:' .. asset_name)
    if not (self.resp) then
      self.status = 500
    end
    if getmetatable(self.resp) == nil then
      self.resp = nil
    end
  elseif 'backends' == _exp_0 then
    self.resp, self.msg = red:smembers('backend:' .. asset_name)
    if type(self.resp) == 'table' and table.getn(self.resp) == 0 then
      self.resp = nil
    end
  else
    self.status = 400
    self.msg = 'Bad asset type. Must be "frontends" or "backends"'
  end
  if self.resp then
    self.status = 200
    self.msg = "OK"
  end
  if self.resp == nil then
    self.status = 404
    self.msg = "Entry does not exist"
  else
    if not (self.status) then
      self.status = 500
    end
    if not (self.msg) then
      self.msg = 'Unknown failutre'
    end
    library.log(self.msg)
  end
  return M.finish(red)
end
M.save_data = function(self, asset_type, asset_name, asset_value, overwrite)
  if overwrite == nil then
    overwrite = false
  end
  local red = M.connect(self)
  if red == nil then
    return nil
  end
  local _exp_0 = asset_type
  if 'frontends' == _exp_0 then
    local ok, err = red:set('frontend:' .. asset_name, asset_value)
  elseif 'backends' == _exp_0 then
    red = M.connect(self)
    if overwrite then
      red:init_pipeline()
    end
    if overwrite then
      red:del('backend:' .. asset_name)
    end
    local ok, err = red:sadd('backend:' .. asset_name, asset_value)
    if overwrite then
      M.commit(self, red, "Failed to save backend: ")
    end
  else
    local ok = false
    self.status = 400
    self.msg = 'Bad asset type. Must be "frontends" or "backends"'
  end
  if ok == nil then
    self.status = 200
    self.msg = "OK"
  else
    self.status = 500
    local err
    if err == nil then
      err = "unknown"
    end
    self.msg = "Failed to save backend: " .. err
    library.log_err(self.msg)
  end
  return M.finish(red)
end
M.delete_data = function(self, asset_type, asset_name, asset_value)
  if asset_value == nil then
    asset_value = nil
  end
  local red = M.connect(self)
  if red == nil then
    return nil
  end
  local _exp_0 = asset_type
  if 'frontends' == _exp_0 then
    local resp
    resp, self.msg = red:del('frontend:' .. asset_name)
    if not (self.resp) then
      self.status = 500
    end
  elseif 'backends' == _exp_0 then
    if asset_value == nil then
      local resp
      resp, self.msg = red:del('backend:' .. asset_name)
    else
      local resp
      resp, self.msg = red:srem('backend:' .. asset_name, asset_value)
    end
  else
    self.status = 400
    self.msg = 'Bad asset type. Must be "frontends" or "backends"'
  end
  if resp == nil then
    if type(self.resp) == 'table' and table.getn(self.resp) == 0 then
      self.resp = nil
    end
    self.status = 200
    if not (self.msg) then
      self.msg = "OK"
    end
  else
    if not (self.status) then
      self.status = 500
    end
    if not (self.msg) then
      self.msg = 'Unknown failutre'
    end
    library.log_err(self.msg)
  end
  return M.finish(red)
end
M.save_batch_data = function(self, data, overwrite)
  if overwrite == nil then
    overwrite = false
  end
  local red = M.connect(self)
  if red == nil then
    return nil
  end
  red:init_pipeline()
  if data['frontends'] then
    local _list_0 = data['frontends']
    for _index_0 = 1, #_list_0 do
      local frontend = _list_0[_index_0]
      if overwrite then
        red:del('frontend:' .. frontend['url'])
      end
      if not (frontend['backend_name'] == nil) then
        library.log('adding frontend: ' .. frontend['url'] .. ' ' .. frontend['backend_name'])
        red:set('frontend:' .. frontend['url'], frontend['backend_name'])
      end
    end
  end
  if data["backends"] then
    local _list_0 = data['backends']
    for _index_0 = 1, #_list_0 do
      local backend = _list_0[_index_0]
      if overwrite then
        red:del('backend:' .. backend["name"])
      end
      if not (type(backend['servers']) == 'table') then
        backend['servers'] = {
          backend['servers']
        }
      end
      local _list_1 = backend['servers']
      for _index_1 = 1, #_list_1 do
        local server = _list_1[_index_1]
        if not (server == nil) then
          library.log('adding backend: ' .. backend["name"] .. ' ' .. server)
          red:sadd('backend:' .. backend["name"], server)
        end
      end
    end
  end
  M.commit(self, red, "failed to save data: ")
  return M.finish(red)
end
M.delete_batch_data = function(self, data)
  local red = M.connect(self)
  if red == nil then
    return nil
  end
  red:init_pipeline()
  if data['frontends'] then
    local _list_0 = data['frontends']
    for _index_0 = 1, #_list_0 do
      local frontend = _list_0[_index_0]
      library.log('deleting frontend: ' .. frontend['url'])
      red:del('frontend:' .. frontend['url'])
    end
  end
  if data["backends"] then
    local _list_0 = data['backends']
    for _index_0 = 1, #_list_0 do
      local backend = _list_0[_index_0]
      if backend['servers'] == nil then
        red:del('backend:' .. backend["name"])
      end
      if backend['servers'] then
        if not (type(backend['servers']) == 'table') then
          backend['servers'] = {
            backend['servers']
          }
        end
        local _list_1 = backend['servers']
        for _index_1 = 1, #_list_1 do
          local server = _list_1[_index_1]
          if not (server == nil) then
            library.log('deleting backend: ' .. backend["name"] .. ' ' .. server)
            red:srem('backend:' .. backend["name"], server)
          end
        end
      end
    end
  end
  M.commit(self, red, "failed to save data: ")
  return M.finish(red)
end
M.fetch_frontend = function(self, max_path_length)
  if max_path_length == nil then
    max_path_length = 3
  end
  local path = self.req.parsed_url['path']
  local path_parts = library.split(path, '/')
  local keys = { }
  local p = ''
  local count = 0
  for k, v in pairs(path_parts) do
    if not (v == nil or v == '') then
      if count < (max_path_length) then
        count = count + 1
        p = p .. "/" .. tostring(v)
        table.insert(keys, 1, self.req.parsed_url['host'] .. p)
      end
    end
  end
  local red = M.connect(self)
  if red == nil then
    return nil
  end
  for _index_0 = 1, #keys do
    local key = keys[_index_0]
    local resp, err = red:get('frontend:' .. key)
    if type(resp) == 'string' then
      M.finish(red)
      return {
        frontend_key = key,
        backend_key = resp
      }
    end
  end
  M.finish(red)
  library.log_err("Frontend Cache miss")
  return nil
end
M.fetch_server = function(self, backend_key)
  local red = M.connect(self)
  if red == nil then
    return nil
  end
  local resp, err = red:srandmember('backend:' .. backend_key)
  if not (err == nil) then
    library.log('Failed getting backend: ' .. err)
  end
  M.finish(red)
  if type(resp) == 'string' then
    return resp
  else
    library.log_err("Backend Cache miss: " .. backend_key)
    return nil
  end
end
return M
