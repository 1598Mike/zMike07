--[[
    Testlauf für die Server-Logik, ganz ohne FiveM.
    Aufruf aus dem Ordner resources/ic_behoerden:   lua tests/run.lua
    Mit Lua 5.4 (die Ressource nutzt lua54).
]]

package.path = './?.lua;' .. package.path

-- Platzhalter für Funktionen, die FiveM bereitstellt
function vector3(x, y, z) return { x = x, y = y, z = z } end
_G.json = nil

local T = dofile('tests/lib.lua')

-- Dateien in derselben Reihenfolge wie im fxmanifest laden
dofile('config.lua')
dofile('config_server.lua')
dofile('shared/util.lua')
dofile('shared/rules.lua')
dofile('shared/protocol.lua')

-- Server-Logik (ohne die FiveM-spezifischen Dateien persist, bridge_*, net, main)
for _, f in ipairs({ 'server/store.lua', 'server/core.lua', 'server/duty.lua', 'server/register.lua', 'server/applications.lua', 'server/appointments.lua', 'server/staff.lua', 'server/api.lua' }) do
    dofile(f)
end
local H = dofile('tests/fakebridge.lua')

local files = {
    'tests/test_util.lua',
    'tests/test_rules.lua',
    'tests/test_flows.lua',
    'tests/test_persist.lua',
    'tests/test_net.lua',
    'tests/test_bridge.lua',
}
for _, f in ipairs(files) do
    local fh = io.open(f, 'r')
    if fh then
        fh:close()
        print('\n' .. f)
        local chunk, err = loadfile(f)
        if not chunk then error(err) end
        chunk(T, H)
    end
end

print('')
local ok = T.run()
os.exit(ok and 0 or 1)
