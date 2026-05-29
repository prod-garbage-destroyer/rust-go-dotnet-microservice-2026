math.randomseed(os.time())

local ids_env = os.getenv("BENCH_USER_IDS")
local ids = {}

if ids_env and ids_env ~= "" then
  for id in string.gmatch(ids_env, "[^,]+") do
    ids[#ids + 1] = id
  end
end

if #ids == 0 then
  ids = {
    "00000000-0000-0000-0000-000000000001"
  }
end

request = function()
  local idx = math.random(#ids)
  return wrk.format("GET", "/users/" .. ids[idx])
end
