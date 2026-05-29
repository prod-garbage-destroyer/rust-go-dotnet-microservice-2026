counter = 0

request = function()
  counter = counter + 1
  local ts = tostring(os.time())
  local email = "bench-" .. ts .. "-" .. tostring(counter) .. "@example.com"
  local body = string.format('{"name":"Bench User %d","email":"%s"}', counter, email)

  return wrk.format(
    "POST",
    "/users",
    {
      ["Content-Type"] = "application/json"
    },
    body
  )
end
