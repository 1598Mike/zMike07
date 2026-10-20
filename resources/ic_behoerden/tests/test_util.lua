local T = ...
local U = IC.util

local fx = dofile('tests/fixtures/normname.lua')

T.test('normName stimmt mit der JavaScript-Version überein', function()
    for _, row in ipairs(fx.norm) do
        T.eq(U.normName(row[1]), row[2], 'normName(' .. row[1] .. ')')
    end
end)

T.test('levenshtein stimmt mit der JavaScript-Version überein', function()
    for _, row in ipairs(fx.lev) do
        T.eq(U.levenshtein(row[1], row[2]), row[3], 'lev(' .. row[1] .. ',' .. row[2] .. ')')
    end
end)

T.test('Rechtsformzusatz wird nur ergänzt, wenn er fehlt', function()
    T.eq(U.withSuffix('Becker Logistik', 'GmbH'), 'Becker Logistik GmbH')
    T.eq(U.withSuffix('Becker Logistik GmbH', 'GmbH'), 'Becker Logistik GmbH')
    T.eq(U.withSuffix('Becker Logistik gmbh', 'GmbH'), 'Becker Logistik gmbh')
    T.eq(U.withSuffix('Hafenbar', ''), 'Hafenbar')
end)

T.test('erlaubte Zeichen im Namen', function()
    T.ok(U.nameCharsOk("Müller & Söhne"))
    T.ok(U.nameCharsOk("Lena's Kiosk 24"))
    T.ok(U.nameCharsOk('Zur Alten Straße'))
    T.notok(U.nameCharsOk('Bar <script>'))
    T.notok(U.nameCharsOk('Café'))        -- é ist nicht erlaubt, wie in der Oberfläche
    T.notok(U.nameCharsOk('Name; DROP'))
end)

T.test('Länge zählt Zeichen, nicht Bytes', function()
    T.eq(U.ulen('Bär'), 3)
    T.eq(U.ulen('Straße'), 6)
    T.eq(U.ulen(''), 0)
end)

T.test('sortBy ist stabil und kann absteigend sortieren', function()
    local l = { { n = 'a', k = 2 }, { n = 'b', k = 1 }, { n = 'c', k = 2 }, { n = 'd', k = 1 } }
    local s = U.sortBy(l, function(x) return x.k end)
    T.eq(s[1].n .. s[2].n .. s[3].n .. s[4].n, 'bdac')
    local d = U.sortBy(l, function(x) return x.k end, true)
    T.eq(d[1].n .. d[2].n .. d[3].n .. d[4].n, 'acbd')
end)
