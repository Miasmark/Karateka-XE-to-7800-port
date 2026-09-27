-- the 7800 build's system symbols (SYM = work/karateka7800.sym): SYM_ADDR[name]
-- and SYM_NAME[addr]
SYM_ADDR, SYM_NAME = {}, {}
for line in io.lines(os.getenv("SYM")) do
  local a, n = line:match("^(%x+) (%S+)")
  if a then a = tonumber(a, 16); SYM_ADDR[n] = a; SYM_NAME[a] = SYM_NAME[a] or n end
end
