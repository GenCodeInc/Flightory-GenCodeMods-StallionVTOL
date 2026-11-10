-- Stallion VTOL wing lights with pre-arm status
-- Two daisy-chained 4-pixel WS2812 boards on S13.
-- First board = LEFT / RED; second board = RIGHT / GREEN.
-- DIN is at the front; DOUT is at the rear of each wing.
--
-- NOT READY (disarmed): nav lights OFF, ALL pixels show status:
--   GPS + EKF not ready  : RED 1 s, AMBER 1 s, alternating
--   GPS not ready only   : RED 1 s on, 1 s off
--   EKF not ready only   : AMBER 1 s on, 1 s off
--   GPS + EKF ok, other  : AMBER fast blink (another pre-arm
--   pre-arm check failing  check is failing, e.g. no radio;
--                          see PreArm: in Messages)
-- READY TO ARM and ARMED: normal nav lights
--   All four pixels show navigation colour,
--   rear two pixels double-flash white.
--
-- Requires SERVO13_FUNCTION = 94 and SCR_ENABLE = 1.
-- Run only ONE script controlling these LEDs.

-- ======================= USER SETTINGS =======================

local LEDS_PER_WING = 4
local NUM_LEDS = 2 * LEDS_PER_WING

local WING1_COLOR = {255, 0, 0}
local WING2_COLOR = {0, 255, 0}
local STROBE_COLOR = {255, 255, 255}

local RED = {255, 0, 0}
local AMBER = {255, 100, 0}
local OFF = {0, 0, 0}

local STROBE_PER_WING = 2

-- true selects the last pixels, toward DOUT / rear.
local WING1_TIP_AT_END = true
local WING2_TIP_AT_END = true

-- Normal mode: double flash, followed by a pause.
local FLASH_MS = 60
local GAP_MS = 80
local PAUSE_MS = 900

-- Status mode blink timing.
local STATUS_HALF_MS = 1000      -- 1 s on / 1 s off
local OTHER_HALF_MS = 250        -- fast blink for "other"

-- How often to re-check GPS / EKF / pre-arm while disarmed.
local STATUS_CHECK_MS = 1000

-- =============================================================

local UPDATE_MS = 20
local REFRESH_MS = 1000
local CYCLE_MS = FLASH_MS + GAP_MS + FLASH_MS + PAUSE_MS

local STATE_TEXT = {
    BOTH  = "no GPS fix + EKF not ready (red/amber)",
    GPS   = "no GPS fix (red blink)",
    EKF   = "EKF not ready (amber blink)",
    OTHER = "other pre-arm check failing (fast amber)",
    READY = "ready to arm (nav lights)",
    ARMED = "armed (nav lights)",
}

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
local last_check_ms = start_ms
local state = nil
local last_render_key = nil

local function in_strobe_set(i, tip_at_end)
    if tip_at_end then
        return i >= LEDS_PER_WING - STROBE_PER_WING
    end
    return i < STROBE_PER_WING
end

local function disarmed_state()
    local gps_ok = gps:status(gps:primary_sensor()) >= gps.GPS_OK_FIX_3D
    -- On a plane, AHRS is only "healthy" once it is actually
    -- using the configured EKF.
    local ekf_ok = ahrs:healthy()

    if not gps_ok and not ekf_ok then
        return "BOTH"
    elseif not gps_ok then
        return "GPS"
    elseif not ekf_ok then
        return "EKF"
    elseif arming:pre_arm_checks() then
        return "READY"
    end
    return "OTHER"
end

local function render_nav(strobe_on)
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

local function render_all(color)
    for i = 0, NUM_LEDS - 1 do
        serialLED:set_RGB(chan, i, color[1], color[2], color[3])
    end
    serialLED:send(chan)
end

local function update()
    local now = millis()

    -- Armed is checked every loop; GPS / EKF / pre-arm
    -- only every STATUS_CHECK_MS.
    local new_state = state
    if arming:is_armed() then
        new_state = "ARMED"
    elseif state == nil or state == "ARMED"
        or (now - last_check_ms):tofloat() >= STATUS_CHECK_MS then
        new_state = disarmed_state()
        last_check_ms = now
    end

    if new_state ~= state then
        state = new_state
        gcs:send_text(6, "STALLION LED: " .. STATE_TEXT[state])
    end

    local key
    local draw

    if state == "ARMED" or state == "READY" then
        -- Normal nav lights with double white strobe.
        -- Subtract timestamps before conversion to handle clock wrap.
        local phase = (now - cycle_start_ms):tofloat()
        if phase >= CYCLE_MS then
            cycle_start_ms = now
            phase = 0
        end
        local second_start = FLASH_MS + GAP_MS
        local strobe_on = phase < FLASH_MS
            or (phase >= second_start
                and phase < second_start + FLASH_MS)
        key = "NAV" .. tostring(strobe_on)
        draw = function() render_nav(strobe_on) end
    else
        -- Status: all pixels, nav lights off.
        local t = (now - start_ms):tofloat()
        local color
        if state == "OTHER" then
            local first = (t % (2 * OTHER_HALF_MS)) < OTHER_HALF_MS
            color = first and AMBER or OFF
        else
            local first = (t % (2 * STATUS_HALF_MS)) < STATUS_HALF_MS
            if state == "BOTH" then
                color = first and RED or AMBER
            elseif state == "GPS" then
                color = first and RED or OFF
            else
                color = first and AMBER or OFF
            end
        end
        key = state .. color[1] .. "," .. color[2]
        draw = function() render_all(color) end
    end

    -- Send on changes, plus a periodic refresh.
    if key ~= last_render_key
        or (now - last_send_ms):tofloat() >= REFRESH_MS then
        draw()
        last_render_key = key
        last_send_ms = now
    end
end

local function protected_wrapper()
    local ok, err = pcall(update)

    if not ok then
        last_render_key = nil
        gcs:send_text(3, "STALLION LED error: " .. tostring(err))
        return protected_wrapper, 1000
    end

    return protected_wrapper, UPDATE_MS
end

gcs:send_text(6, "STALLION LED: status lights v2 started")
return protected_wrapper()
