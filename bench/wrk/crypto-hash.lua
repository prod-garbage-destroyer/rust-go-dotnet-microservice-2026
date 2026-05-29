counter = 0

request = function()
  counter = counter + 1
  local body = string.format(
    '{"input":"benchmark-payload-%d-abcdefghijklmnopqrstuvwxyz0123456789","rounds":2000}',
    counter
  )

  return wrk.format(
    "POST",
    "/crypto/hash",
    {
      ["Content-Type"] = "application/json"
    },
    body
  )
end
