--[[
    ic_behoerden · Konfiguration für Client und Server

    Diese Datei wird an alle Spieler übertragen. Hier steht deshalb nur, was der Client braucht:
    Orte und Bedienung. Gebühren, Regeln, Webhooks und Hooks stehen in config_server.lua.
]]

Config = Config or {}

Config.City = 'Los Santos'

-- Orte der Terminals. Die Koordinaten sind Platzhalter beim Rathaus von Los Santos.
-- ANPASSEN: Stellt euch im Spiel an den gewünschten Ort und übernehmt die Koordinaten.
-- Empfehlung: Gewerbeamt und Bürgeramt im selben Gebäude.
Config.Locations = {
    gewerbeamt = {
        { coords = vector3(-544.90, -204.40, 38.22), radius = 1.8, label = 'Gewerbeamt-Terminal' },
    },
    buergeramt = {
        { coords = vector3(-540.90, -208.00, 38.22), radius = 1.8, label = 'Bürgeramt-Empfang' },
    },
    -- Beamten-Schalter: Hier öffnen Beamte das Tablet und führen Termine.
    beamte = {
        { coords = vector3(-537.60, -212.20, 38.22), radius = 1.6, label = 'Beamten-Schalter' },
    },
}

-- Wie nah ein Spieler dem Ort sein muss, damit der Server Aufrufe annimmt (Meter, zusätzlich zum Radius).
Config.Tolerance = 3.0

Config.Interact = {
    -- 'marker': Marker am Boden und Taste. 'target': Ziel-Auswahl über ox_target (die Ressource muss laufen).
    mode = 'marker',
    key = 38,                  -- E
    helpText = 'Drücke ~INPUT_PICKUP~, um %s zu öffnen.',
    drawDistance = 8.0,        -- Marker sichtbar bis zu dieser Entfernung
    marker = { type = 20, r = 15, g = 76, b = 129, a = 160 },
}

-- Eigene Benachrichtigung statt der Meldung am Bildschirmrand (läuft im Client). kind: 'info', 'ok', 'warn', 'bad'.
-- Beispiel für ox_lib:  Config.Notify = function(text, kind) lib.notify({ description = text, type = kind == 'ok' and 'success' or kind == 'bad' and 'error' or kind == 'warn' and 'warning' or 'inform' }) end
Config.Notify = nil

Config.Blips = {
    enabled = true,
    gewerbeamt = { sprite = 351, colour = 3, scale = 0.8, label = 'Gewerbeamt und Bürgeramt' },
    -- Es wird nur ein Blip pro Ort der Gruppe "gewerbeamt" gesetzt, damit die Karte ruhig bleibt.
}
