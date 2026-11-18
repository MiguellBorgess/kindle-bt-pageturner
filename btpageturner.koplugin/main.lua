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

local EVENTS_FILE = "/tmp/btpageturner.events"
local PID_FILE = "/tmp/btpageturner.pid"
local POLL_INTERVAL = 0.3 -- seconds between checks
local BYTES_PER_EVENT = 2 -- each tap writes "1\n"

-- Folder containing this file (to find listener.sh)
local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/") or "."

local BTPageTurner = WidgetContainer:extend{
    name = "btpageturner",
    is_doc_only = true, -- only loaded while a book is open
}

function BTPageTurner:init()
    if not Device:isKindle() then return end
    self.last_size = 0
    self.poll = function()
        self:check()
        UIManager:scheduleIn(POLL_INTERVAL, self.poll)
    end
    self:startListener()
    UIManager:scheduleIn(POLL_INTERVAL, self.poll)
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
        for _ = 1, taps do
            self.ui:handleEvent(Event:new("GotoViewRel", 1))
        end
        UIManager.event_hook:execute("InputEvent") -- Prevent autosuspend
    end
end

function BTPageTurner:onSuspend()
    UIManager:unschedule(self.poll)
end

function BTPageTurner:onResume()
    self:discardPending()
    UIManager:unschedule(self.poll)
    UIManager:scheduleIn(POLL_INTERVAL, self.poll)
end

function BTPageTurner:onCloseDocument()
    if self.poll then UIManager:unschedule(self.poll) end
    self:stopListener()
end

return BTPageTurner
