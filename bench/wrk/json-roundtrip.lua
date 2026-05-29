counter = 0

local function build_payload(seq)
  local items = {}
  for i = 1, 10 do
    items[#items + 1] = string.format(
      '{"id":"item-%d-%d","score":%d,"enabled":%s,"tags":["alpha","beta","gamma","delta"]}',
      seq,
      i,
      i * 11,
      (i % 2 == 0) and "true" or "false"
    )
  end

  return string.format(
    '{"tenant":"bench","region":"us-east-1","timestamp":"2026-05-08T00:00:00Z","items":[%s]}',
    table.concat(items, ",")
  )
end

request = function()
  counter = counter + 1
  local body = build_payload(counter)
  return wrk.format(
    "POST",
    "/json/roundtrip",
    {
      ["Content-Type"] = "application/json"
    },
    body
  )
end
