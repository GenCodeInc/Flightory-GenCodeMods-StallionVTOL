-- Stallion VTOL: four-pattern LED demonstration
-- Two daisy-chained 4-pixel WS2812 boards on S13.
-- Requires SERVO13_FUNCTION = 94 and SCR_ENABLE = 1.
-- Run ONLY ONE LED script at a time.
-- Demo effects replace normal navigation lighting.

local NUM_LEDS = 8
local LEDS_PER_WING = 4
local PATTERN_MS = 5000
local UPDATE_MS = 20

-- Overall brightness: 0-255.
-- All-white effects draw more current than single colours.
local BRIGHTNESS = 120

local NAMES = {
    "UFO orbit",
    "Police pursuit",
    "Rainbow chase",
    "Reactor pulse"
}

local chan = SRV_Channels:find_channel(94)

if chan == nil then
    gcs:send_text(3, "STALLION DEMO: Script Out 1 not found")
    return
end

-- Convert zero-based SRV channel to one-based serialLED channel.
chan = chan + 1

assert(serialLED:set_num_neopixel(chan, NUM_LEDS),
       "STALLION DEMO: NeoPixel setup failed")

local function pixel(i, r, g, b)
    local scale = BRIGHTNESS / 255
    serialLED:set_RGB(
        chan,
        i,
        math.floor(r * scale + 0.5),
        math.floor(g * scale + 0.5),
        math.floor(b * scale + 0.5)
    )
end

local function fill(r, g, b)
    for i = 0, NUM_LEDS - 1 do
        pixel(i, r, g, b)
    end
end

-- Pattern 1: comet orbit through all eight pixels.
local function ufo(t)
    fill(0, 0, 0)

    local head = math.floor(t / 100) % NUM_LEDS

    -- Draw the fading purple trail behind the white/pink head.
    pixel((head - 3) % NUM_LEDS, 15, 0, 30)
    pixel((head - 2) % NUM_LEDS, 45, 0, 90)
    pixel((head - 1) % NUM_LEDS, 120, 0, 220)
    pixel(head, 255, 150, 255)
end

-- Pattern 2: red double flash, then blue double flash.
-- Wing colours swap every full second.
local function police(t)
    fill(0, 0, 0)

    local phase = t % 1000
    local swap = math.floor(t / 1000) % 2 == 1
    local first_on = phase < 70
        or (phase >= 140 and phase < 210)
    local second_on = (phase >= 500 and phase < 570)
        or (phase >= 640 and phase < 710)

    for i = 0, LEDS_PER_WING - 1 do
        if first_on then
            if swap then
                pixel(i, 0, 0, 255)
            else
                pixel(i, 255, 0, 0)
            end
        end

        if second_on then
            if swap then
                pixel(i + LEDS_PER_WING, 255, 0, 0)
            else
                pixel(i + LEDS_PER_WING, 0, 0, 255)
            end
        end
    end
end

-- Colour wheel: hue 0-1 -> full-saturation RGB.
local function rainbow_color(h)
    local x = (h % 1) * 6
    local section = math.floor(x)
    local rising = (x - section) * 255
    local falling = 255 - rising

    if section == 0 then
        return 255, rising, 0
    elseif section == 1 then
        return falling, 255, 0
    elseif section == 2 then
        return 0, 255, rising
    elseif section == 3 then
        return 0, falling, 255
    elseif section == 4 then
        return rising, 0, 255
    end
    return 255, 0, falling
end

-- Pattern 3: continuously moving rainbow.
local function rainbow(t)
    for i = 0, NUM_LEDS - 1 do
        local hue = i / NUM_LEDS + t / 1800
        local r, g, b = rainbow_color(hue)
        pixel(i, r, g, b)
    end
end

-- Pattern 4: cyan energy pulse with a white flash at its peak.
local function reactor(t)
    local phase = t % 1000

    if phase >= 460 and phase < 540 then
        fill(255, 255, 255)
    else
        local wave = (1 - math.cos(
            2 * math.pi * phase / 1000)) / 2
        local level = 15 + 240 * wave
        fill(0, level, level)
    end
end

local PATTERNS = {ufo, police, rainbow, reactor}
local pattern = 1
local pattern_start = millis()

local function update()
    local now = millis()
    local elapsed = (now - pattern_start):tofloat()

    if elapsed >= PATTERN_MS then
        pattern = pattern % #PATTERNS + 1
        pattern_start = now
        elapsed = 0
        gcs:send_text(6, "STALLION DEMO: " .. NAMES[pattern])
    end

    PATTERNS[pattern](elapsed)
    serialLED:send(chan)
end

local function protected_wrapper()
    local ok, err = pcall(update)

    if not ok then
        gcs:send_text(3, "STALLION DEMO error: " .. tostring(err))
        return protected_wrapper, 1000
    end

    return protected_wrapper, UPDATE_MS
end

gcs:send_text(6, "STALLION DEMO: " .. NAMES[pattern])
return protected_wrapper()