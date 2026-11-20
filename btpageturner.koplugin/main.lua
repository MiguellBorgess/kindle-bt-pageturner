--[[
BT page turner: turns the page in KOReader when you tap the button
of Bluetooth earbuds connected to the Kindle.

How it works:
  1. listener.sh listens for the LIPC event "BTavrcpCommand"
     (published by com.lab126.btfd when the earbuds send play/pause)
     and appends a "1" line to a file for every tap.
  2. This plugin checks that file's size a few times per second.
     It grew = there was a tap = turn the page.
--]]

local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")

local EVENTS_FILE = "/tmp/btpageturner.events"
local PID_FILE = "/tmp/btpageturner.pid"
local POLL_INTERVAL = 0.3 -- seconds between checks
local BYTES_PER_EVENT = 2 -- each tap writes "1\n"

-- Folder containing this file (to find listener.sh)
local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/") or "."

-- Name of the connected Bluetooth device, or nil if none
local function getConnectedDevice()
    local p = io.popen("lipc-get-prop com.lab126.btfd BTconnectedDevName 2>/dev/null")
    if not p then return nil end
    local name = p:read("*l")
    p:close()
    if name and name ~= "" then return name end
    return nil
end

local BTPageTurner = WidgetContainer:extend{
    name = "btpageturner",
    is_doc_only = true,
}

function BTPageTurner:init()
    if not Device:isKindle() then return end
    self.enabled = G_reader_settings:nilOrTrue("btpageturner_enabled")    
    self.last_size = 0
    self.ui.menu:registerToMainMenu(self)
    self.poll = function()
        self:check()
        UIManager:scheduleIn(POLL_INTERVAL, self.poll)
    end
    if self.enabled then self:start() end
end

function BTPageTurner:addToMainMenu(menu_items)
    menu_items.bt_page_turner = self:getBtPageTurnerMenu()
end

function BTPageTurner:getBtPageTurnerMenu()
    return {
        text = _("BT Page Turner"),
        sorting_hint = "navi",
        checked_func = function() return self.enabled end,
        sub_item_table = {
            {
                text = _("Enabled"),
                checked_func = function() return self.enabled end,
                callback = function()
                    self.enabled = not self.enabled
                    G_reader_settings:saveSetting("btpageturner_enabled", self.enabled)
                    if self.enabled then self:start()
                    else self:stop() end
                end,
            },
            {
                text_func = function()
                    local name = getConnectedDevice()
                    if name then
                        return _("Connected: ") .. name
                    end
                    return _("No device connected")
                end,
                keep_menu_open = true,
                separator = true,
            },
            {
                text = _("Version: ") .. (self.version or "?"),
                keep_menu_open = true,
            },
        },
    }
end

function BTPageTurner:start()
    self:startListener()
    UIManager:unschedule(self.poll)
    UIManager:scheduleIn(POLL_INTERVAL, self.poll)
end

function BTPageTurner:stop()
    UIManager:unschedule(self.poll)
    self:stopListener()
end

function BTPageTurner:startListener()
    self:stopListener()
    -- Start with an empty events file
    local f = io.open(EVENTS_FILE, "w")
    if f then f:close() end
    self.last_size = 0
    -- Run the listener in the background and save its PID
    local cmd = string.format("sh '%s/listener.sh' '%s' >/dev/null 2>&1 & echo $! > '%s'",
        PLUGIN_DIR, EVENTS_FILE, PID_FILE)
    os.execute(cmd)
    logger.info("btpageturner: listener started")
end

function BTPageTurner:stopListener()
    local f = io.open(PID_FILE, "r")
    if not f then return end
    local pid = tonumber(f:read("*l") or "")
    f:close()
    if pid then
        os.execute("kill " .. pid .. " 2>/dev/null")
        logger.info("btpageturner: listener stopped")
    end
    os.remove(PID_FILE)
end

-- Ignore queued taps (e.g. while the Kindle was asleep)
function BTPageTurner:discardPending()
    self.last_size = lfs.attributes(EVENTS_FILE, "size") or 0
end

function BTPageTurner:check()
    local size = lfs.attributes(EVENTS_FILE, "size")
    if not size then return end
    if size > self.last_size then
        local taps = math.floor((size - self.last_size) / BYTES_PER_EVENT)
        self.last_size = size
        for i = 1, taps do
            self.ui:handleEvent(Event:new("GotoViewRel", 1))
        end
        UIManager.event_hook:execute("InputEvent") -- Prevent autosuspend
    end
end

function BTPageTurner:onSuspend()
    UIManager:unschedule(self.poll)
end

function BTPageTurner:onResume()
    if not self.enabled then return end
    self:discardPending()
    UIManager:unschedule(self.poll)
    UIManager:scheduleIn(POLL_INTERVAL, self.poll)
end

function BTPageTurner:onCloseDocument()
    if not self.poll then return end
    self:stop()
end

return BTPageTurner
