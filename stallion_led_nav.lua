-- Stallion VTOL wing lights
-- Two daisy-chained 4-pixel WS2812 boards on S13.
-- First board = LEFT / RED; second board = RIGHT / GREEN.
-- DIN is at the front; DOUT is at the rear of each wing.
--
-- Between flashes: all four pixels show navigation colour.
-- During flashes: rear two turn white; front two stay coloured.
--
-- Requires SERVO13_FUNCTION = 94 and SCR_ENABLE = 1.
-- Run only ONE script controlling these LEDs.

-- ======================= USER SETTINGS =======================

local LEDS_PER_WING = 4
local NUM_LEDS = 2 * LEDS_PER_WING

local WING1_COLOR = {255, 0, 0}
local WING2_COLOR = {0, 255, 0}
local STROBE_COLOR = {255, 255, 255}

local STROBE_PER_WING = 2

-- true selects the last pixels, toward DOUT / rear.
local WING1_TIP_AT_END = true
local WING2_TIP_AT_END = true

-- Double flash, followed by a pause.
local FLASH_MS = 60
local GAP_MS = 80
local PAUSE_MS = 900

-- false lets strobes run during disarmed bench testing.
local STROBE_ONLY_WHEN_ARMED = false

-- =============================================================

local UPDATE_MS = 20
local REFRESH_MS = 1000
local HEARTBEAT_MS = 5000
local HEARTBEAT_WINDOW_MS = 60000
local CYCLE_MS = FLASH_MS + GAP_MS + FLASH_MS + PAUSE_MS

assert(STROBE_PER_WING >= 1
       and STROBE_PER_WING <= LEDS_PER_WING
       and STROBE_PER_WING == math.floor(STROBE_PER_WING),
       "STALLION LED: invalid strobe pixel count")

local chan = SRV_Channels:find_channel(94)

if chan == nil then
    gcs:send_text(3, "STALLION LED: Script Out 1 not found")
    return
end

-- SRV_Channels is zero-based; serialLED is one-based.
chan = chan + 1

assert(serialLED:set_num_neopixel(chan, NUM_LEDS),
       "STALLION LED: NeoPixel setup failed")

local start_ms = millis()
local cycle_start_ms = start_ms
local last_send_ms = start_ms
local last_heartbeat_ms = start_ms
local heartbeat_finished = false
local last_strobe_state = nil

local function in_strobe_set(i, tip_at_end)
    if tip_at_end then
        return i >= LEDS_PER_WING - STROBE_PER_WING
    end
    return i < STROBE_PER_WING
end

local function render(strobe_on)
    for wing = 1, 2 do
        local base = (wing - 1) * LEDS_PER_WING
        local nav = WING1_COLOR
        local tip_at_end = WING1_TIP_AT_END

        if wing == 2 then
            nav = WING2_COLOR
            tip_at_end = WING2_TIP_AT_END
        end

        for i = 0, LEDS_PER_WING - 1 do
            local color = nav

            if strobe_on and in_strobe_set(i, tip_at_end) then
                color = STROBE_COLOR
            end

            serialLED:set_RGB(
                chan, base + i, color[1], color[2], color[3])
        end
    end

    serialLED:send(chan)
end

local function update()
    local now = millis()

    -- Subtract timestamps before conversion to handle clock wrap.
    local phase = (now - cycle_start_ms):tofloat()
    if phase >= CYCLE_MS then
        cycle_start_ms = now
        phase = 0
    end

    local second_start = FLASH_MS + GAP_MS
    local flash_on = phase < FLASH_MS
        or (phase >= second_start
            and phase < second_start + FLASH_MS)

    local enabled = not STROBE_ONLY_WHEN_ARMED
        or arming:is_armed()
    local strobe_on = enabled and flash_on

    -- Send on changes, plus a periodic refresh.
    if strobe_on ~= last_strobe_state
        or (now - last_send_ms):tofloat() >= REFRESH_MS then
        render(strobe_on)
        last_strobe_state = strobe_on
        last_send_ms = now
    end

    -- Status messages only during the first minute.
    if not heartbeat_finished then
        local elapsed = (now - start_ms):tofloat()

        if elapsed > HEARTBEAT_WINDOW_MS then
            heartbeat_finished = true
        elseif (now - last_heartbeat_ms):tofloat()
            >= HEARTBEAT_MS then
            gcs:send_text(
                6, "STALLION LED: nav + strobes running")
            last_heartbeat_ms = now
        end
    end
end

local function protected_wrapper()
    local ok, err = pcall(update)

    if not ok then
        last_strobe_state = nil
        gcs:send_text(3, "STALLION LED error: " .. tostring(err))
        return protected_wrapper, 1000
    end

    return protected_wrapper, UPDATE_MS
end

gcs:send_text(6, "STALLION LED: nav + double strobes started")
return protected_wrapper()