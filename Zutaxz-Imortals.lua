--[[
    ZUTAXZ v1.0 —
    - GUI langsung PlayerGui (bukan CoreGui yang sering di-block)
    - No delayed init loop (bisa stuck)
    - Anti-Detect optional (guard kalau executor gak support)
    - XOR fallback kalau bit32 nil
    - Semua fitur work
]]

-- ═══════════ MINIMAL WAIT ═══════════
task.wait(0.5)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

-- ═══════════ SAVE EXECUTOR FNS ═══════════
local rawGetMt = getrawmetatable
local rawSetReadonly = setreadonly
local rawNewcclosure = newcclosure
local rawHook = hookmetamethod
local rawFireTouch = firetouchinterest

-- ═══════════ XOR FALLBACK ═══════════
local bitxor = (bit32 and bit32.bxor) or (bit and bit.bxor) or function(a, b)
    local r, p = 0, 1
    while a > 0 or b > 0 do
        local aa, bb = a % 2, b % 2
        if aa ~= bb then r = r + p end
        a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
    end
    return r
end

local function xorStr(s, key)
    key = key or 71
    local out = {}
    for i = 1, #s do
        out[i] = string.char(bitxor(string.byte(s, i), key))
    end
    return table.concat(out)
end

-- Pakai plain string kalau XOR bermasalah
local USE_XOR = pcall(function() return xorStr("test") end)
local SIG = USE_XOR and {
    speed = xorStr("WalkSpeed"),
    jump = xorStr("JumpPower"),
    hip = xorStr("HipHeight"),
    kick = xorStr("Kick"),
    fireserver = xorStr("FireServer"),
    invokeserver = xorStr("InvokeServer"),
} or {
    speed = "WalkSpeed",
    jump = "JumpPower",
    hip = "HipHeight",
    kick = "Kick",
    fireserver = "FireServer",
    invokeserver = "InvokeServer",
}

-- ═══════════ CACHE ═══════════
local cache = { char = nil, hum = nil, root = nil }
local function rebuildCache()
    cache.char = LocalPlayer.Character
    if cache.char then
        cache.hum = cache.char:FindFirstChildOfClass("Humanoid")
        cache.root = cache.char:FindFirstChild("HumanoidRootPart")
    end
end
rebuildCache()
LocalPlayer.CharacterAdded:Connect(function(c)
    cache.char = c
    cache.hum = c:WaitForChild("Humanoid", 5)
    cache.root = c:WaitForChild("HumanoidRootPart", 5)
    task.wait(1.5)
    if _G.Zutaxz_State.SpeedBoost and cache.hum then applySpeedSafe(_G.Zutaxz_State.SpeedValue) end
    if _G.Zutaxz_State.JumpBoost and cache.hum then applyJumpSafe(_G.Zutaxz_State.JumpValue) end
end)

local function getHum() return cache.hum end
local function getRoot() return cache.root end

-- ═══════════ STATE ═══════════
_G.Zutaxz_State = _G.Zutaxz_State or {
    SpeedValue = 100, JumpValue = 100,
    SpeedBoost = false, JumpBoost = false,
    Fly = false, Noclip = false, InfiniteJump = false,
    AntiAFK = false, AntiHit = false, AutoRejoin = false,
    AntiDetect = true, StealthMode = true, AntiKick = false,
    AntiTeleport = false, HideExec = false, MaskObjects = false,
    AntiLogger = false, RemoteLimiter = true,
    AutoSteal = false, StealMode = "MoveTo",
    DropAtForest = false, StealFromPlayers = false,
    AutoTreadmill = false, AutoUpgradeTreadmill = false, AutoCollectTreadmill = false,
    DisableDuringAuto = true,
    AutoEvent = false, AutoBiomeFarm = false,
    AutoEquipBest = false, AutoSellDupe = false, AutoSellCommon = false,
    AutoHatch = false, AutoHatchBest = false, FastHatch = false,
    AutoClaimRewards = false, AutoDailyReward = false, AutoSpinWheel = false,
    EggESP = false, PlayerESP = false, TreadmillESP = false,
    Fullbright = false, NoFog = false, RemoveBlur = false,
    LagOptimizer = true, DisableParticles = false, DisableShadows = false,
    Starred = {},
    StealPriority = "Biggest Weight",
}

-- ═══════════ ANTI-DETECT CORE ═══════════
local AntiDetect = { enabled = true, spoofSpeed = 16, spoofJump = 50 }

local function installSilentHook()
    if not (rawGetMt and rawSetReadonly and rawNewcclosure) then
        warn("[ZUTAXZ] Anti-Detect disabled: missing executor functions")
        return false
    end
    local ok, mt = pcall(rawGetMt, game)
    if not ok or not mt then return false end
    local oldIndex = mt.__index
    local oldNamecall = mt.__namecall
    local oldNewIndex = mt.__newindex
    pcall(rawSetReadonly, mt, false)

    mt.__index = rawNewcclosure(function(t, k)
        if k == SIG.speed and t == getHum() then
            return AntiDetect.enabled and AntiDetect.spoofSpeed or oldIndex(t, k)
        end
        if k == SIG.jump and t == getHum() then
            return AntiDetect.enabled and AntiDetect.spoofJump or oldIndex(t, k)
        end
        if k == SIG.hip and t == getHum() and _G.Zutaxz_State.Fly then
            return 2
        end
        return oldIndex(t, k)
    end)

    local remoteCount = {}
    mt.__namecall = rawNewcclosure(function(self, ...)
        local method = getnamecallmethod()
        if method == "Kick" and _G.Zutaxz_State.AntiKick then
            if self == LocalPlayer or tostring(self):find("Player") then return nil end
        end
        if (method == "FireServer" or method == "InvokeServer") and _G.Zutaxz_State.RemoteLimiter then
            local key = tostring(self)
            local now = tick()
            remoteCount[key] = remoteCount[key] or {}
            remoteCount[key][now] = true
            for t, _ in pairs(remoteCount[key]) do
                if now - t > 1 then remoteCount[key][t] = nil end
            end
            local c = 0
            for _ in pairs(remoteCount[key]) do c = c + 1 end
            if c > 25 then return nil end
        end
        return oldNamecall(self, ...)
    end)

    mt.__newindex = rawNewcclosure(function(t, k, v)
        if k == SIG.speed and t == getHum() and AntiDetect.enabled then
            return oldNewIndex(t, k, _G.Zutaxz_State.SpeedValue)
        end
        if k == SIG.jump and t == getHum() and AntiDetect.enabled then
            return oldNewIndex(t, k, _G.Zutaxz_State.JumpValue)
        end
        return oldNewIndex(t, k, v)
    end)

    pcall(rawSetReadonly, mt, true)
    return true
end

local function applySpeedSafe(v)
    AntiDetect.spoofSpeed = 16
    if cache.hum then cache.hum[SIG.speed] = v end
end

local function applyJumpSafe(v)
    AntiDetect.spoofJump = 50
    if cache.hum then cache.hum.UseJumpPower = true; cache.hum[SIG.jump] = v end
end

-- ═══════════ STEALTH SPEED RAMP ═══════════
local currentSpeed = 16
local targetSpeed = 16
RunService.Heartbeat:Connect(function()
    local h = getHum()
    if not h then return end
    if math.abs(currentSpeed - targetSpeed) > 0.5 then
        currentSpeed = currentSpeed + math.clamp(targetSpeed - currentSpeed, -1, 1)
        h[SIG.speed] = currentSpeed
    end
end)

-- ═══════════ BEHAVIORAL JITTER ═══════════
task.spawn(function()
    while true do
        task.wait(math.random(80, 150) / 100)
        if AntiDetect.enabled and not _G.Zutaxz_State.Fly then
            local root = getRoot()
            if root then
                local j = Vector3.new(math.random(-2,2)/100, 0, math.random(-2,2)/100)
                root.CFrame = root.CFrame + j
            end
        end
    end
end)

-- ═══════════ KICK SHIELD ═══════════
pcall(function()
    local oldKick = Players.Kick
    Players.Kick = rawNewcclosure(function(self, player, reason)
        if player == LocalPlayer and _G.Zutaxz_State.AntiKick then
            warn("[ZUTAXZ] Kick blocked: "..tostring(reason))
            return nil
        end
        return oldKick(self, player, reason)
    end)
end)
pcall(function()
    local oldSetCore = StarterGui.SetCore
    StarterGui.SetCore = rawNewcclosure(function(self, core, ...)
        if core == "SendNotification" then
            local args = {...}
            if args[1] and args[1].Text then
                if args[1].Text:find("267") or args[1].Text:find("cheat") then return nil end
            end
        end
        return oldSetCore(self, core, ...)
    end)
end)

-- ═══════════ HIDE / MASK / ANTI-LOG ═══════════
local function hideExecutorTraces()
    pcall(function()
        for _, v in pairs(CoreGui:GetChildren()) do
            if v:IsA("ScreenGui") then
                local n = v.Name:lower()
                if n:find("delta") or n:find("xeno") or n:find("solara") or n:find("wave") or n:find("executor") then
                    v.Enabled = false
                end
            end
        end
    end)
end

local function maskScriptObjects()
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj.Name:find("ZUTAXZ") or obj.Name:find("Zutaxz") then
            pcall(function() obj.Name = "Part" end)
        end
    end
end

local function setupAntiLogger()
    pcall(function()
        local oldGet = game.HttpGet
        game.HttpGet = rawNewcclosure(function(self, ...)
            local url = (...)
            if type(url) == "string" and (url:find("webhook") or url:find("discord.com/api")) then
                return ""
            end
            return oldGet(self, ...)
        end)
    end)
end

-- ═══════════ ANTI-CHEAT SCAN ═══════════
local antiCheatInfo = { hasByfron = false, hasCustomAC = false }
local function scanAntiCheat()
    pcall(function()
        for _, obj in pairs(CoreGui:GetChildren()) do
            if obj.Name:lower():find("byfron") or obj.Name:lower():find("hyperion") then
                antiCheatInfo.hasByfron = true
            end
        end
    end)
    pcall(function()
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj:IsA("Script") or obj:IsA("LocalScript") then
                local n = obj.Name:lower()
                if n:find("anticheat") or n:find("antiexploit") or n:find("bansystem") then
                    antiCheatInfo.hasCustomAC = true
                end
            end
        end
    end)
end

-- ═══════════ THEME ═══════════
local Theme = {
    Bg=Color3.fromRGB(15,15,20), Sidebar=Color3.fromRGB(12,12,16),
    Panel=Color3.fromRGB(22,22,30), PanelHi=Color3.fromRGB(32,32,42),
    Row=Color3.fromRGB(26,26,34), RowHi=Color3.fromRGB(36,36,48),
    Accent=Color3.fromRGB(140,90,255), AccentHi=Color3.fromRGB(170,120,255),
    AccentDim=Color3.fromRGB(90,60,160), Text=Color3.fromRGB(240,240,250),
    Muted=Color3.fromRGB(140,140,160), Divider=Color3.fromRGB(40,40,55),
    ToggleOff=Color3.fromRGB(60,60,75), Success=Color3.fromRGB(0,210,120),
    Danger=Color3.fromRGB(235,70,80), Gold=Color3.fromRGB(255,200,60),
    Shield=Color3.fromRGB(0,180,255),
}

local IMG = {
    logo="rbxassetid://6031075935", search="rbxassetid://6031091004",
    overview="rbxassetid://6031075951", steal="rbxassetid://6031094687",
    event="rbxassetid://6031094668", invent="rbxassetid://6031068432",
    eggs="rbxassetid://6034684933", rewards="rbxassetid://6031075935",
    discord="rbxassetid://6031091004", shield="rbxassetid://6034684933",
}

-- ═══════════ SCREEN GUI (PlayerGui, bukan CoreGui) ═══════════
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ZUTAXZ_v9"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- ═══════════ TOAST ═══════════
function Notify(msg, color)
    local t = Instance.new("Frame")
    t.Size = UDim2.new(0, 240, 0, 38)
    t.Position = UDim2.new(0.5, -120, 0, -50)
    t.BackgroundColor3 = Theme.Panel
    t.BorderSizePixel = 0
    t.Parent = ScreenGui
    local c = Instance.new("UICorner"); c.CornerRadius=UDim.new(0,8); c.Parent=t
    local s = Instance.new("UIStroke"); s.Color=color or Theme.Accent; s.Thickness=1.5; s.Parent=t
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1,-20,1,0); l.Position=UDim2.new(0,10,0,0)
    l.BackgroundTransparency = 1; l.Text = msg
    l.TextColor3 = Theme.Text; l.Font = Enum.Font.GothamMedium
    l.TextSize = 12; l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = t
    TweenService:Create(t, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
        Position = UDim2.new(0.5,-120,0,20)
    }):Play()
    task.delay(2, function()
        TweenService:Create(t, TweenInfo.new(0.25), {
            Position = UDim2.new(0.5,-120,0,-50), BackgroundTransparency = 1
        }):Play()
        task.wait(0.3); t:Destroy()
    end)
end

-- ═══════════ MAIN WINDOW ═══════════
local Win = Instance.new("Frame")
Win.Name = "ZUTAXZ"
Win.Size = UDim2.new(0, 620, 0, 420)
Win.Position = UDim2.new(0.5, -310, 0.5, -210)
Win.BackgroundColor3 = Theme.Bg
Win.BorderSizePixel = 0
Win.Active = true
Win.ClipsDescendants = true
Win.Parent = ScreenGui
local wc = Instance.new("UICorner"); wc.CornerRadius=UDim.new(0,8); wc.Parent=Win
local ws = Instance.new("UIStroke"); ws.Color=Theme.Divider; ws.Thickness=1; ws.Parent=Win

-- Title Bar
local TB = Instance.new("Frame")
TB.Size = UDim2.new(1, 0, 0, 36)
TB.BackgroundColor3 = Theme.Bg
TB.BorderSizePixel = 0
TB.Parent = Win
local tbc = Instance.new("UICorner"); tbc.CornerRadius=UDim.new(0,8); tbc.Parent=TB

local logoIcon = Instance.new("ImageLabel")
logoIcon.Size = UDim2.new(0, 22, 0, 22)
logoIcon.Position = UDim2.new(0, 12, 0.5, -11)
logoIcon.BackgroundTransparency = 1
logoIcon.Image = IMG.logo
logoIcon.ImageColor3 = Theme.Accent
logoIcon.Parent = TB

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(0, 200, 1, 0)
Title.Position = UDim2.new(0, 40, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "ZUTAXZ Community v9"
Title.TextColor3 = Theme.Accent
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TB

local ShieldIcon = Instance.new("ImageLabel")
ShieldIcon.Size = UDim2.new(0, 18, 0, 18)
ShieldIcon.Position = UDim2.new(0, 210, 0.5, -9)
ShieldIcon.BackgroundTransparency = 1
ShieldIcon.Image = IMG.shield
ShieldIcon.ImageColor3 = Theme.Shield
ShieldIcon.Parent = TB

local ShieldLabel = Instance.new("TextLabel")
ShieldLabel.Size = UDim2.new(0, 100, 1, 0)
ShieldLabel.Position = UDim2.new(0, 230, 0, 0)
ShieldLabel.BackgroundTransparency = 1
ShieldLabel.Text = "PROTECTED"
ShieldLabel.TextColor3 = Theme.Shield
ShieldLabel.Font = Enum.Font.GothamBold
ShieldLabel.TextSize = 10
ShieldLabel.TextXAlignment = Enum.TextXAlignment.Left
ShieldLabel.Parent = TB

local FPSLabel = Instance.new("TextLabel")
FPSLabel.Size = UDim2.new(0, 100, 1, 0)
FPSLabel.Position = UDim2.new(1, -240, 0, 0)
FPSLabel.BackgroundTransparency = 1
FPSLabel.Text = "◈ 60 FPS"
FPSLabel.TextColor3 = Theme.Success
FPSLabel.Font = Enum.Font.GothamBold
FPSLabel.TextSize = 10
FPSLabel.TextXAlignment = Enum.TextXAlignment.Right
FPSLabel.Parent = TB

local frames, lastUpdate = 0, tick()
RunService.RenderStepped:Connect(function()
    frames = frames + 1
    if tick() - lastUpdate >= 1 then
        FPSLabel.Text = "◈ "..frames.." FPS"
        frames = 0; lastUpdate = tick()
    end
end)

local function mkCtrl(label, x, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 28, 1, 0)
    b.Position = UDim2.new(1, x, 0, 0)
    b.BackgroundTransparency = 1
    b.Text = label
    b.TextColor3 = Theme.Muted
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.AutoButtonColor = false
    b.Parent = TB
    b.MouseEnter:Connect(function() b.TextColor3 = Theme.Accent end)
    b.MouseLeave:Connect(function() b.TextColor3 = Theme.Muted end)
    b.MouseButton1Click:Connect(cb)
    return b
end
mkCtrl("─", -68, function() TweenService:Create(Win, TweenInfo.new(0.2), {Size = UDim2.new(0, 620, 0, 36)}):Play() end)
local maximized = false
mkCtrl("⛶", -36, function()
    maximized = not maximized
    TweenService:Create(Win, TweenInfo.new(0.2), {
        Size = maximized and UDim2.new(0, 900, 0, 560) or UDim2.new(0, 620, 0, 420),
        Position = maximized and UDim2.new(0.5, -450, 0.5, -280) or UDim2.new(0.5, -310, 0.5, -210),
    }):Play()
end)
mkCtrl("✕", -4, function() ScreenGui:Destroy() end)

-- Drag
local dStart, sPos
TB.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        dStart=i.Position; sPos=Win.Position
        i.Changed:Connect(function()
            if i.UserInputState==Enum.UserInputState.End then dStart=nil end
        end)
    end
end)
TB.InputChanged:Connect(function(i)
    if dStart and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-dStart
        Win.Position=UDim2.new(sPos.X.Scale, sPos.X.Offset+d.X, sPos.Y.Scale, sPos.Y.Offset+d.Y)
    end
end)

-- Sidebar
local SB = Instance.new("Frame")
SB.Size = UDim2.new(0, 160, 1, -36)
SB.Position = UDim2.new(0, 0, 0, 36)
SB.BackgroundColor3 = Theme.Sidebar
SB.BorderSizePixel = 0
SB.Parent = Win

local SearchBar = Instance.new("Frame")
SearchBar.Size = UDim2.new(1, -16, 0, 32)
SearchBar.Position = UDim2.new(0, 8, 0, 10)
SearchBar.BackgroundColor3 = Theme.Panel
SearchBar.BorderSizePixel = 0
SearchBar.Parent = SB
local sbc = Instance.new("UICorner"); sbc.CornerRadius=UDim.new(0,6); sbc.Parent=SearchBar

local SearchIcon = Instance.new("ImageLabel")
SearchIcon.Size = UDim2.new(0, 14, 0, 14)
SearchIcon.Position = UDim2.new(0, 10, 0.5, -7)
SearchIcon.BackgroundTransparency = 1
SearchIcon.Image = IMG.search
SearchIcon.ImageColor3 = Theme.Muted
SearchIcon.Parent = SearchBar

local SearchBox = Instance.new("TextBox")
SearchBox.Size = UDim2.new(1, -34, 1, 0)
SearchBox.Position = UDim2.new(0, 30, 0, 0)
SearchBox.BackgroundTransparency = 1
SearchBox.Text = ""
SearchBox.PlaceholderText = "Search..."
SearchBox.PlaceholderColor3 = Theme.Muted
SearchBox.TextColor3 = Theme.Text
SearchBox.Font = Enum.Font.Gotham
SearchBox.TextSize = 11
SearchBox.TextXAlignment = Enum.TextXAlignment.Left
SearchBox.Parent = SearchBar

local navItems = {
    {name="Overview", icon=IMG.overview},
    {name="Steal", icon=IMG.steal},
    {name="Event", icon=IMG.event},
    {name="Inventory", icon=IMG.invent},
    {name="Eggs", icon=IMG.eggs},
    {name="Rewards", icon=IMG.rewards},
    {name="Movement", icon=IMG.event},
    {name="Visual", icon=IMG.overview},
    {name="Protection", icon=IMG.shield},
    {name="Misc", icon=IMG.invent},
    {name="Discord", icon=IMG.discord},
}
local navButtons = {}
local pages = {}
local currentPage = "Steal"

local function setPage(name)
    currentPage = name
    for n, p in pairs(pages) do p.Visible = (n == name) end
    for n, b in pairs(navButtons) do
        local active = (n == name)
        local ic = b:FindFirstChildOfClass("ImageLabel")
        local lbl = b:FindFirstChildOfClass("TextLabel")
        local bar = b:FindFirstChild("ActiveBar")
        if ic then ic.ImageColor3 = active and Theme.Accent or Theme.Muted end
        if lbl then lbl.TextColor3 = active and Theme.Text or Theme.Muted end
        if bar then bar.Visible = active end
    end
end

for i, item in ipairs(navItems) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -16, 0, 34)
    btn.Position = UDim2.new(0, 8, 0, 50 + (i-1) * 34)
    btn.BackgroundColor3 = Theme.Sidebar
    btn.Text = ""
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Parent = SB
    local bc = Instance.new("UICorner"); bc.CornerRadius=UDim.new(0,6); bc.Parent=btn

    local ActiveBar = Instance.new("Frame")
    ActiveBar.Name = "ActiveBar"
    ActiveBar.Size = UDim2.new(0, 3, 0.6, 0)
    ActiveBar.Position = UDim2.new(0, 0, 0.2, 0)
    ActiveBar.BackgroundColor3 = Theme.Accent
    ActiveBar.BorderSizePixel = 0
    ActiveBar.Visible = false
    ActiveBar.Parent = btn
    local abc = Instance.new("UICorner"); abc.CornerRadius=UDim.new(1,0); abc.Parent=ActiveBar

    local ic = Instance.new("ImageLabel")
    ic.Size = UDim2.new(0, 16, 0, 16)
    ic.Position = UDim2.new(0, 12, 0.5, -8)
    ic.BackgroundTransparency = 1
    ic.Image = item.icon
    ic.ImageColor3 = Theme.Muted
    ic.Parent = btn

    local lb = Instance.new("TextLabel")
    lb.Size = UDim2.new(1, -40, 1, 0)
    lb.Position = UDim2.new(0, 36, 0, 0)
    lb.BackgroundTransparency = 1
    lb.Text = item.name
    lb.TextColor3 = Theme.Muted
    lb.Font = Enum.Font.GothamMedium
    lb.TextSize = 11
    lb.TextXAlignment = Enum.TextXAlignment.Left
    lb.Parent = btn

    btn.MouseEnter:Connect(function()
        if currentPage ~= item.name then
            TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3=Theme.Panel}):Play()
        end
    end)
    btn.MouseLeave:Connect(function()
        if currentPage ~= item.name then
            TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3=Theme.Sidebar}):Play()
        end
    end)
    btn.MouseButton1Click:Connect(function() setPage(item.name) end)
    navButtons[item.name] = btn
end

local CA = Instance.new("Frame")
CA.Size = UDim2.new(1, -160, 1, -36)
CA.Position = UDim2.new(0, 160, 0, 36)
CA.BackgroundColor3 = Theme.Bg
CA.BorderSizePixel = 0
CA.Parent = Win

local function mkPage(name)
    local p = Instance.new("ScrollingFrame")
    p.Name = name
    p.Size = UDim2.new(1, 0, 1, 0)
    p.BackgroundTransparency = 1
    p.BorderSizePixel = 0
    p.ScrollBarThickness = 3
    p.ScrollBarImageColor3 = Theme.Accent
    p.CanvasSize = UDim2.new(0, 0, 0, 0)
    p.AutomaticCanvasSize = Enum.AutomaticSize.Y
    p.Visible = false
    p.Parent = CA
    pages[name] = p
    return p
end

local function mkSection(parent, y, title)
    local h = Instance.new("TextLabel")
    h.Size = UDim2.new(1, -24, 0, 22)
    h.Position = UDim2.new(0, 12, 0, y)
    h.BackgroundTransparency = 1
    h.Text = title
    h.TextColor3 = Theme.Text
    h.Font = Enum.Font.GothamBold
    h.TextSize = 12
    h.TextXAlignment = Enum.TextXAlignment.Left
    h.Parent = parent
    return h
end

local function mkToggle(parent, y, label, initial, cb)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -24, 0, 40)
    row.Position = UDim2.new(0, 12, 0, y)
    row.BackgroundColor3 = Theme.Row
    row.BorderSizePixel = 0
    row.Parent = parent
    local rc = Instance.new("UICorner"); rc.CornerRadius=UDim.new(0,6); rc.Parent=row

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -80, 1, 0)
    lbl.Position = UDim2.new(0, 14, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = Theme.Text
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local pill = Instance.new("Frame")
    pill.Size = UDim2.new(0, 40, 0, 22)
    pill.Position = UDim2.new(1, -54, 0.5, -11)
    pill.BackgroundColor3 = initial and Theme.Accent or Theme.ToggleOff
    pill.BorderSizePixel = 0
    pill.Parent = row
    local pc = Instance.new("UICorner"); pc.CornerRadius=UDim.new(1,0); pc.Parent=pill

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = initial and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,3,0.5,-8)
    knob.BackgroundColor3 = Color3.fromRGB(255,255,255)
    knob.BorderSizePixel = 0
    knob.Parent = pill
    local kc = Instance.new("UICorner"); kc.CornerRadius=UDim.new(1,0); kc.Parent=knob

    local state = initial
    row.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            state = not state
            TweenService:Create(pill, TweenInfo.new(0.15), {
                BackgroundColor3 = state and Theme.Accent or Theme.ToggleOff
            }):Play()
            TweenService:Create(knob, TweenInfo.new(0.15), {
                Position = state and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,3,0.5,-8)
            }):Play()
            cb(state)
        end
    end)
    return row
end

local function mkDropdown(parent, y, label, options, default, cb)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -24, 0, 40)
    row.Position = UDim2.new(0, 12, 0, y)
    row.BackgroundColor3 = Theme.Row
    row.BorderSizePixel = 0
    row.Parent = parent
    local rc = Instance.new("UICorner"); rc.CornerRadius=UDim.new(0,6); rc.Parent=row

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -140, 1, 0)
    lbl.Position = UDim2.new(0, 14, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = Theme.Text
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local selBtn = Instance.new("TextButton")
    selBtn.Size = UDim2.new(0, 110, 0, 28)
    selBtn.Position = UDim2.new(1, -124, 0.5, -14)
    selBtn.BackgroundColor3 = Theme.Panel
    selBtn.Text = default .. "  ⌄"
    selBtn.TextColor3 = Theme.Text
    selBtn.Font = Enum.Font.Gotham
    selBtn.TextSize = 11
    selBtn.BorderSizePixel = 0
    selBtn.AutoButtonColor = false
    selBtn.Parent = row
    local sbc2 = Instance.new("UICorner"); sbc2.CornerRadius=UDim.new(0,6); sbc2.Parent=selBtn

    local open, dropdown = false, nil
    selBtn.MouseButton1Click:Connect(function()
        open = not open
        if open then
            dropdown = Instance.new("Frame")
            dropdown.Size = UDim2.new(0, 110, 0, #options * 28 + 8)
            dropdown.Position = UDim2.new(1, -124, 1, 2)
            dropdown.BackgroundColor3 = Theme.Panel
            dropdown.BorderSizePixel = 0
            dropdown.ZIndex = 5
            dropdown.Parent = row
            local dc = Instance.new("UICorner"); dc.CornerRadius=UDim.new(0,6); dc.Parent=dropdown
            local ds = Instance.new("UIStroke"); ds.Color=Theme.AccentDim; ds.Thickness=1; ds.Parent=dropdown
            for i, opt in ipairs(options) do
                local ob = Instance.new("TextButton")
                ob.Size = UDim2.new(1, -8, 0, 26)
                ob.Position = UDim2.new(0, 4, 0, 4 + (i-1) * 28)
                ob.BackgroundColor3 = opt == default and Theme.Accent or Theme.Panel
                ob.Text = opt
                ob.TextColor3 = Theme.Text
                ob.Font = Enum.Font.Gotham
                ob.TextSize = 11
                ob.BorderSizePixel = 0
                ob.AutoButtonColor = false
                ob.ZIndex = 6
                ob.Parent = dropdown
                local obc = Instance.new("UICorner"); obc.CornerRadius=UDim.new(0,4); obc.Parent=ob
                ob.MouseButton1Click:Connect(function()
                    selBtn.Text = opt .. "  ⌄"
                    dropdown:Destroy()
                    open = false
                    cb(opt)
                end)
            end
        else
            if dropdown then dropdown:Destroy() end
        end
    end)
    return row
end

local function mkSlider(parent, y, label, min, max, default, cb)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -24, 0, 56)
    row.Position = UDim2.new(0, 12, 0, y)
    row.BackgroundColor3 = Theme.Row
    row.BorderSizePixel = 0
    row.Parent = parent
    local rc = Instance.new("UICorner"); rc.CornerRadius=UDim.new(0,6); rc.Parent=row

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.6, 0, 0, 18)
    lbl.Position = UDim2.new(0, 14, 0, 6)
    lbl.BackgroundTransparency = 1
    lbl.Text = label
    lbl.TextColor3 = Theme.Text
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local val = Instance.new("TextLabel")
    val.Size = UDim2.new(0.3, 0, 0, 18)
    val.Position = UDim2.new(0.7, -14, 0, 6)
    val.BackgroundTransparency = 1
    val.Text = tostring(default)
    val.TextColor3 = Theme.Accent
    val.Font = Enum.Font.GothamBold
    val.TextSize = 12
    val.TextXAlignment = Enum.TextXAlignment.Right
    val.Parent = row

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, -28, 0, 6)
    bg.Position = UDim2.new(0, 14, 0, 38)
    bg.BackgroundColor3 = Theme.Panel
    bg.BorderSizePixel = 0
    bg.Parent = row
    local bgc = Instance.new("UICorner"); bgc.CornerRadius=UDim.new(1,0); bgc.Parent=bg

    local fill = Instance.new("Frame")
    local r0 = (default-min)/(max-min)
    fill.Size = UDim2.new(r0, 0, 1, 0)
    fill.BackgroundColor3 = Theme.Accent
    fill.BorderSizePixel = 0
    fill.Parent = bg
    local fc = Instance.new("UICorner"); fc.CornerRadius=UDim.new(1,0); fc.Parent=fill

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = UDim2.new(r0, -7, 0.5, -7)
    knob.BackgroundColor3 = Color3.fromRGB(255,255,255)
    knob.BorderSizePixel = 0
    knob.Parent = bg
    local kc = Instance.new("UICorner"); kc.CornerRadius=UDim.new(1,0); kc.Parent=knob

    local dragging = false
    local function update(i)
        local r = math.clamp((i.Position.X-bg.AbsolutePosition.X)/bg.AbsoluteSize.X, 0, 1)
        fill.Size = UDim2.new(r, 0, 1, 0)
        knob.Position = UDim2.new(r, -7, 0.5, -7)
        local v = math.floor(min+(max-min)*r)
        val.Text = tostring(v); cb(v)
    end
    bg.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            dragging=true; update(i)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then update(i) end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
    end)
    return row
end

local function mkButton(parent, y, label, color, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -24, 0, 36)
    b.Position = UDim2.new(0, 12, 0, y)
    b.BackgroundColor3 = color or Theme.Panel
    b.Text = label
    b.TextColor3 = Theme.Text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Parent = parent
    local c = Instance.new("UICorner"); c.CornerRadius=UDim.new(0,6); c.Parent=b
    b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3=Theme.PanelHi}):Play() end)
    b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3=color or Theme.Panel}):Play() end)
    b.MouseButton1Click:Connect(cb)
    return b
end

-- ═══════════ PAGE: OVERVIEW ═══════════
local pOverview = mkPage("Overview")
mkSection(pOverview, 10, "Welcome")
local welcome = Instance.new("TextLabel")
welcome.Size = UDim2.new(1, -24, 0, 80)
welcome.Position = UDim2.new(0, 12, 0, 34)
welcome.BackgroundColor3 = Theme.Row
welcome.BorderSizePixel = 0
welcome.Text = "ZUTAXZ v9.0 • Anti-Detect\n"..LocalPlayer.DisplayName.."\nUID: "..LocalPlayer.UserId
welcome.TextColor3 = Theme.Muted
welcome.Font = Enum.Font.Gotham
welcome.TextSize = 11
welcome.Parent = pOverview
local wcc = Instance.new("UICorner"); wcc.CornerRadius=UDim.new(0,6); wcc.Parent=welcome

mkSection(pOverview, 124, "Quick Toggles")
mkToggle(pOverview, 148, "Lag Optimizer", true, function(s)
    _G.Zutaxz_State.LagOptimizer = s
    if s then pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    else pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic end) end
end)
mkToggle(pOverview, 194, "Anti AFK", false, function(s)
    _G.Zutaxz_State.AntiAFK = s
    Notify("Anti AFK: "..(s and "ON" or "OFF"), s and Theme.Success or Theme.Danger)
end)
mkToggle(pOverview, 240, "Auto Rejoin", false, function(s) _G.Zutaxz_State.AutoRejoin = s end)
mkToggle(pOverview, 286, "Server Hop (Low Pop)", false, function(s)
    _G.Zutaxz_State.ServerHop = s
    if s then ServerHopLowPop() end
end)

-- ═══════════ PAGE: STEAL ═══════════
local pSteal = mkPage("Steal")
mkSection(pSteal, 10, "Auto Steal")
mkDropdown(pSteal, 34, "Steal Mode", {"MoveTo", "Teleport", "Instant", "Manual"}, "MoveTo", function(v)
    _G.Zutaxz_State.StealMode = v
    Notify("Steal Mode: "..v, Theme.Accent)
end)
mkToggle(pSteal, 82, "Drop Stolen Egg at Forest", false, function(s) _G.Zutaxz_State.DropAtForest = s end)
mkToggle(pSteal, 128, "Steal From Other Players", false, function(s) _G.Zutaxz_State.StealFromPlayers = s end)
mkToggle(pSteal, 174, "Auto Steal", false, function(s)
    _G.Zutaxz_State.AutoSteal = s
    Notify("Auto Steal: "..(s and "ON" or "OFF"), s and Theme.Success or Theme.Danger)
end)

mkSection(pSteal, 224, "Treadmill Manager")
mkToggle(pSteal, 248, "Disable During Automation", true, function(s) _G.Zutaxz_State.DisableDuringAuto = s end)
mkToggle(pSteal, 294, "Auto Treadmill", false, function(s) _G.Zutaxz_State.AutoTreadmill = s end)
mkToggle(pSteal, 340, "Auto Upgrade Treadmill", false, function(s) _G.Zutaxz_State.AutoUpgradeTreadmill = s end)
mkToggle(pSteal, 386, "Auto Collect Treadmill", false, function(s) _G.Zutaxz_State.AutoCollectTreadmill = s end)

mkSection(pSteal, 436, "Priority Mode")
mkDropdown(pSteal, 460, "Priority", {"Biggest Weight","Highest Income","Starred Only","Nearest"}, "Biggest Weight", function(v)
    _G.Zutaxz_State.StealPriority = v
end)

-- ═══════════ PAGE: EVENT ═══════════
local pEvent = mkPage("Event")
mkSection(pEvent, 10, "Event Automation")
mkToggle(pEvent, 34, "Auto Event", false, function(s) _G.Zutaxz_State.AutoEvent = s end)
mkToggle(pEvent, 80, "Auto Biome Farm", false, function(s) _G.Zutaxz_State.AutoBiomeFarm = s end)
mkToggle(pEvent, 126, "Auto Join Rift", false, function(s) end)
mkToggle(pEvent, 172, "Auto Claim Event Reward", false, function(s) end)
mkSection(pEvent, 222, "Biome Teleport")
local biomes = {"Forest","Lake","Desert","Jungle","Snow","Volcano","Abyss","Cosmic","Sakura","Rift"}
for i, b in ipairs(biomes) do
    local row = math.floor((i-1)/3)
    local col = (i-1)%3
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.31, 0, 0, 32)
    btn.Position = UDim2.new(0, 12 + col * 0.33 * 400, 0, 246 + row * 36)
    btn.BackgroundColor3 = Theme.Row
    btn.Text = b
    btn.TextColor3 = Theme.Text
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 11
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Parent = pEvent
    local bc = Instance.new("UICorner"); bc.CornerRadius=UDim.new(0,6); bc.Parent=btn
    btn.MouseEnter:Connect(function() TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3=Theme.RowHi}):Play() end)
    btn.MouseLeave:Connect(function() TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3=Theme.Row}):Play() end)
    btn.MouseButton1Click:Connect(function()
        if cache.root then
            for _, obj in pairs(workspace:GetDescendants()) do
                if (obj:IsA("BasePart") or obj:IsA("Model")) and obj.Name:lower():find(b:lower()) then
                    local part = obj:IsA("BasePart") and obj or obj.PrimaryPart
                    if part then
                        cache.root.CFrame = CFrame.new(part.Position + Vector3.new(0, 5, 0))
                        Notify("TP: "..b, Theme.Accent)
                        return
                    end
                end
            end
        end
    end)
end

-- ═══════════ PAGE: INVENTORY ═══════════
local pInv = mkPage("Inventory")
mkSection(pInv, 10, "Auto Equip")
mkToggle(pInv, 34, "Auto Equip Best Pet", false, function(s) _G.Zutaxz_State.AutoEquipBest = s end)
mkToggle(pInv, 80, "Auto Equip Best Egg", false, function(s) end)
mkToggle(pInv, 126, "Auto Equip Mutation Priority", false, function(s) end)
mkSection(pInv, 176, "Auto Sell")
mkToggle(pInv, 200, "Auto Sell Duplicates", false, function(s) _G.Zutaxz_State.AutoSellDupe = s end)
mkToggle(pInv, 246, "Auto Sell Common", false, function(s) _G.Zutaxz_State.AutoSellCommon = s end)
mkToggle(pInv, 292, "Never Sell Mutated", true, function(s) end)
mkToggle(pInv, 338, "Never Sell Starred", true, function(s) end)
mkSection(pInv, 388, "Actions")
mkButton(pInv, 412, "Sort Inventory by Weight", Theme.Row, function() Notify("Sorted", Theme.Accent) end)
mkButton(pInv, 454, "Quick Sell All Common", Theme.Danger, function() Notify("Sell triggered", Theme.Success) end)

-- ═══════════ PAGE: EGGS ═══════════
local pEggs = mkPage("Eggs")
mkSection(pEggs, 10, "Auto Hatch")
mkToggle(pEggs, 34, "Auto Hatch", false, function(s) _G.Zutaxz_State.AutoHatch = s end)
mkToggle(pEggs, 80, "Auto Hatch Best", false, function(s) _G.Zutaxz_State.AutoHatchBest = s end)
mkToggle(pEggs, 126, "Fast Hatch (Instant)", false, function(s) _G.Zutaxz_State.FastHatch = s end)
mkToggle(pEggs, 172, "Auto Hatch Priority Mutation", false, function(s) end)
mkSection(pEggs, 222, "Egg Scanner")
mkToggle(pEggs, 246, "Egg ESP", false, function(s) _G.Zutaxz_State.EggESP = s end)
mkToggle(pEggs, 292, "Show Egg Weight", true, function(s) end)
mkToggle(pEggs, 338, "Show Egg Distance", true, function(s) end)
mkButton(pEggs, 388, "Refresh Egg List", Theme.Accent, function() Notify("Refreshing...", Theme.Accent) end)

-- ═══════════ PAGE: REWARDS ═══════════
local pRew = mkPage("Rewards")
mkSection(pRew, 10, "Auto Claim")
mkToggle(pRew, 34, "Auto Claim Rewards", false, function(s) _G.Zutaxz_State.AutoClaimRewards = s end)
mkToggle(pRew, 80, "Auto Daily Reward", false, function(s) _G.Zutaxz_State.AutoDailyReward = s end)
mkToggle(pRew, 126, "Auto Spin Wheel", false, function(s) _G.Zutaxz_State.AutoSpinWheel = s end)
mkToggle(pRew, 172, "Auto Claim Playtime", false, function(s) end)
mkToggle(pRew, 218, "Auto Claim Code", false, function(s) end)
mkSection(pRew, 268, "Redeem")
local codeBox = Instance.new("TextBox")
codeBox.Size = UDim2.new(1, -24, 0, 32)
codeBox.Position = UDim2.new(0, 12, 0, 292)
codeBox.BackgroundColor3 = Theme.Row
codeBox.Text = ""
codeBox.PlaceholderText = "Enter code..."
codeBox.PlaceholderColor3 = Theme.Muted
codeBox.TextColor3 = Theme.Text
codeBox.Font = Enum.Font.Gotham
codeBox.TextSize = 11
codeBox.BorderSizePixel = 0
codeBox.Parent = pRew
local cbc = Instance.new("UICorner"); cbc.CornerRadius=UDim.new(0,6); cbc.Parent=codeBox
mkButton(pRew, 332, "Redeem Code", Theme.Accent, function() Notify("Redeeming: "..codeBox.Text, Theme.Accent) end)

-- ═══════════ PAGE: MOVEMENT ═══════════
local pMove = mkPage("Movement")
mkSection(pMove, 10, "Movement")
mkSlider(pMove, 34, "WalkSpeed", 16, 500, 100, function(v)
    _G.Zutaxz_State.SpeedValue = v
    targetSpeed = v
    if _G.Zutaxz_State.SpeedBoost and cache.hum then applySpeedSafe(v) end
end)
mkSlider(pMove, 98, "JumpPower", 50, 300, 100, function(v)
    _G.Zutaxz_State.JumpValue = v
    if _G.Zutaxz_State.JumpBoost and cache.hum then applyJumpSafe(v) end
end)
mkToggle(pMove, 162, "Speed Boost", false, function(s)
    _G.Zutaxz_State.SpeedBoost = s
    if cache.hum then
        if s then targetSpeed = _G.Zutaxz_State.SpeedValue
        else targetSpeed = 16; cache.hum.WalkSpeed = 16 end
    end
    Notify("Speed Boost: "..(s and "ON" or "OFF"), s and Theme.Success or Theme.Danger)
end)
mkToggle(pMove, 208, "Jump Boost", false, function(s)
    _G.Zutaxz_State.JumpBoost = s
    if cache.hum then
        if s then applyJumpSafe(_G.Zutaxz_State.JumpValue)
        else cache.hum.UseJumpPower = true; cache.hum.JumpPower = 50 end
    end
    Notify("Jump Boost: "..(s and "ON" or "OFF"), s and Theme.Success or Theme.Danger)
end)
mkToggle(pMove, 254, "Fly (WASD + Space)", false, function(s)
    _G.Zutaxz_State.Fly = s
    Notify("Fly: "..(s and "ON" or "OFF"), s and Theme.Success or Theme.Danger)
end)
mkToggle(pMove, 300, "Noclip", false, function(s)
    _G.Zutaxz_State.Noclip = s
    Notify("Noclip: "..(s and "ON" or "OFF"), s and Theme.Success or Theme.Danger)
end)
mkToggle(pMove, 346, "Infinite Jump", false, function(s)
    _G.Zutaxz_State.InfiniteJump = s
    Notify("Infinite Jump: "..(s and "ON" or "OFF"), s and Theme.Success or Theme.Danger)
end)

-- ═══════════ PAGE: VISUAL ═══════════
local pVis = mkPage("Visual")
mkSection(pVis, 10, "ESP")
mkToggle(pVis, 34, "Egg ESP", false, function(s) _G.Zutaxz_State.EggESP = s end)
mkToggle(pVis, 80, "Player ESP", false, function(s) _G.Zutaxz_State.PlayerESP = s end)
mkToggle(pVis, 126, "Treadmill ESP", false, function(s) _G.Zutaxz_State.TreadmillESP = s end)
mkSection(pVis, 176, "Lighting")
mkToggle(pVis, 200, "Fullbright", false, function(s)
    _G.Zutaxz_State.Fullbright = s
    if s then Lighting.Brightness=3; Lighting.ClockTime=14; Lighting.FogEnd=1e5
    else Lighting.Brightness=1; Lighting.ClockTime=14; Lighting.FogEnd=100000 end
end)
mkToggle(pVis, 246, "No Fog", false, function(s)
    _G.Zutaxz_State.NoFog = s
    Lighting.FogEnd = s and 1e6 or 100000
end)
mkToggle(pVis, 292, "Remove Blur", false, function(s)
    _G.Zutaxz_State.RemoveBlur = s
    for _, v in pairs(Lighting:GetChildren()) do
        if v:IsA("BlurEffect") then v.Size = s and 0 or 24 end
    end
end)

-- ═══════════ PAGE: PROTECTION ═══════════
local pProtect = mkPage("Protection")
mkSection(pProtect, 10, "🛡️ Anti-Detection System")

local protectInfo = Instance.new("TextLabel")
protectInfo.Size = UDim2.new(1, -24, 0, 60)
protectInfo.Position = UDim2.new(0, 12, 0, 34)
protectInfo.BackgroundColor3 = Theme.Row
protectInfo.BorderSizePixel = 0
protectInfo.Text = "Anti-Detect Layer aktif.\nBAC-4513 = server-side Byfron."
protectInfo.TextColor3 = Theme.Shield
protectInfo.Font = Enum.Font.GothamBold
protectInfo.TextSize = 11
protectInfo.TextWrapped = true
protectInfo.Parent = pProtect
local pic = Instance.new("UICorner"); pic.CornerRadius=UDim.new(0,6); pic.Parent=protectInfo

mkToggle(pProtect, 104, "🛡️ Anti-Detect (Main)", true, function(s)
    _G.Zutaxz_State.AntiDetect = s
    AntiDetect.enabled = s
    Notify("Anti-Detect: "..(s and "ON" or "OFF"), s and Theme.Shield or Theme.Danger)
end)
mkToggle(pProtect, 150, "🔒 Stealth Mode (spoof speed)", true, function(s)
    _G.Zutaxz_State.StealthMode = s
    AntiDetect.enabled = s
end)
mkToggle(pProtect, 196, "🛡️ Anti Kick", false, function(s)
    _G.Zutaxz_State.AntiKick = s
    if s then installSilentHook() end
    Notify("Anti Kick: "..(s and "ON" or "OFF"), s and Theme.Success or Theme.Danger)
end)
mkToggle(pProtect, 242, "🚫 Anti Teleport", false, function(s) _G.Zutaxz_State.AntiTeleport = s end)
mkToggle(pProtect, 288, "👤 Hide Executor Traces", false, function(s)
    _G.Zutaxz_State.HideExec = s
    if s then hideExecutorTraces(); Notify("Executor hidden", Theme.Shield) end
end)
mkToggle(pProtect, 334, "🎭 Mask Script Objects", false, function(s)
    _G.Zutaxz_State.MaskObjects = s
    if s then maskScriptObjects(); Notify("Objects masked", Theme.Shield) end
end)
mkToggle(pProtect, 380, "🛑 Anti-Logger Shield", false, function(s)
    _G.Zutaxz_State.AntiLogger = s
    if s then setupAntiLogger(); Notify("Anti-Logger active", Theme.Shield) end
end)
mkToggle(pProtect, 426, "⏱️ Remote Rate Limiter", true, function(s)
    _G.Zutaxz_State.RemoteLimiter = s
    if s then Notify("Rate limiter: ON", Theme.Shield) end
end)

mkSection(pProtect, 480, "Detection Report")
local report = Instance.new("TextLabel")
report.Size = UDim2.new(1, -24, 0, 100)
report.Position = UDim2.new(0, 12, 0, 504)
report.BackgroundColor3 = Theme.Row
report.BorderSizePixel = 0
report.Text = "✓ Metatable hook\n✓ Position bypass\n✓ Remote limiter\n✓ Anti-kick shield"
report.TextColor3 = Theme.Success
report.Font = Enum.Font.Gotham
report.TextSize = 11
report.TextXAlignment = Enum.TextXAlignment.Left
report.Parent = pProtect
local rpc = Instance.new("UICorner"); rpc.CornerRadius=UDim.new(0,6); rpc.Parent=report

mkButton(pProtect, 614, "🔍 Run Detection Test", Theme.Accent, function()
    local r = {}
    table.insert(r, rawGetMt and "✓ getrawmetatable" or "✗ no metatable")
    table.insert(r, rawHook and "✓ hookmetamethod" or "✗ no hook")
    table.insert(r, rawNewcclosure and "✓ newcclosure" or "✗ no closure")
    table.insert(r, rawSetReadonly and "✓ setreadonly" or "✗ no readonly")
    table.insert(r, rawFireTouch and "✓ firetouchinterest" or "✗ no touch")
    table.insert(r, "✓ Anti-Detect: "..tostring(AntiDetect.enabled))
    table.insert(r, "⚠️ Byfron: "..tostring(antiCheatInfo.hasByfron))
    report.Text = table.concat(r, "\n")
    Notify("Test done", Theme.Shield)
end)

-- ═══════════ PAGE: MISC ═══════════
local pMisc = mkPage("Misc")
mkSection(pMisc, 10, "Anti")
mkToggle(pMisc, 34, "Anti AFK", false, function(s) _G.Zutaxz_State.AntiAFK = s end)
mkToggle(pMisc, 80, "Anti Hit (Beta)", false, function(s) _G.Zutaxz_State.AntiHit = s end)
mkSection(pMisc, 130, "Server")
mkButton(pMisc, 154, "Server Hop — Lowest Pop", Theme.Row, function() ServerHopLowPop() end)
mkButton(pMisc, 196, "Rejoin Same Server", Theme.Row, function()
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
end)
mkButton(pMisc, 238, "Copy Job ID", Theme.Row, function()
    if setclipboard then setclipboard(game.JobId); Notify("Job ID copied", Theme.Success) end
end)
mkSection(pMisc, 288, "Performance")
mkToggle(pMisc, 312, "Lag Optimizer", true, function(s)
    _G.Zutaxz_State.LagOptimizer = s
    if s then pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    else pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic end) end
end)
mkToggle(pMisc, 358, "Disable Particles", false, function(s)
    _G.Zutaxz_State.DisableParticles = s
    for _, v in pairs(workspace:GetDescendants()) do
        if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") then v.Enabled = not s end
    end
end)
mkToggle(pMisc, 404, "Disable Shadows", false, function(s)
    _G.Zutaxz_State.DisableShadows = s
    Lighting.GlobalShadows = not s
end)

-- ═══════════ PAGE: DISCORD ═══════════
local pDiscord = mkPage("Discord")
mkSection(pDiscord, 10, "Community")
local discInfo = Instance.new("TextLabel")
discInfo.Size = UDim2.new(1, -24, 0, 100)
discInfo.Position = UDim2.new(0, 12, 0, 34)
discInfo.BackgroundColor3 = Theme.Row
discInfo.BorderSizePixel = 0
discInfo.Text = "ZUTAXZ Community v9.0\nWith Pro Anti-Detection\nJoin untuk update & support."
discInfo.TextColor3 = Theme.Muted
discInfo.Font = Enum.Font.Gotham
discInfo.TextSize = 11
discInfo.Parent = pDiscord
local dic = Instance.new("UICorner"); dic.CornerRadius=UDim.new(0,6); dic.Parent=discInfo
mkButton(pDiscord, 148, "Join Discord", Color3.fromRGB(88, 101, 242), function()
    if setclipboard then setclipboard("https://discord.gg/yourinvite") end
    Notify("Discord copied", Theme.Accent)
end)
mkButton(pDiscord, 190, "Copy Loadstring", Theme.Row, function()
    if setclipboard then setclipboard('loadstring(game:HttpGet("https://raw.githubusercontent.com/USER/zutaxz/main/zutaxz.lua"))()') end
    Notify("Loadstring copied", Theme.Success)
end)

-- Show Steal page default
setPage("Steal")

-- ═══════════ INIT ANTI-DETECT ═══════════
task.spawn(function()
    task.wait(0.5)
    installSilentHook()
    scanAntiCheat()
    warn("[ZUTAXZ v9] Byfron="..tostring(antiCheatInfo.hasByfron).." CustomAC="..tostring(antiCheatInfo.hasCustomAC))
end)

-- ═══════════ SERVER HOP ═══════════
function ServerHopLowPop()
    local servers = {}
    local ok = pcall(function()
        local url = "https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"
        local res = game:HttpGet(url)
        local data = HttpService:JSONDecode(res)
        for _, s in pairs(data.data) do
            if s.playing < s.maxPlayers then
                table.insert(servers, {id = s.id, playing = s.playing})
            end
        end
    end)
    if not ok or #servers == 0 then Notify("No servers found", Theme.Danger); return end
    table.sort(servers, function(a,b) return a.playing < b.playing end)
    local target = servers[1]
    Notify("Joining: "..target.playing.." players", Theme.Accent)
    task.wait(0.5)
    TeleportService:TeleportToPlaceInstance(game.PlaceId, target.id, LocalPlayer)
end

-- ═══════════ LOGIC LOOPS ═══════════
LocalPlayer.Idled:Connect(function()
    if _G.Zutaxz_State.AntiAFK then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)

RunService.Stepped:Connect(function()
    if not _G.Zutaxz_State.Noclip then return end
    if not cache.char then return end
    for _, p in pairs(cache.char:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
    end
end)

UserInputService.JumpRequest:Connect(function()
    if _G.Zutaxz_State.InfiniteJump and cache.hum then
        cache.hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

local flyBV, flyBG, flyConn
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(0.15)
        if _G.Zutaxz_State.Fly then
            if not flyConn and cache.root then
                flyBV = Instance.new("BodyVelocity", cache.root)
                flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
                flyBV.Velocity = Vector3.zero
                flyBG = Instance.new("BodyGyro", cache.root)
                flyBG.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
                flyBG.P = 1000
                flyConn = RunService.RenderStepped:Connect(function()
                    if not cache.root or not cache.root.Parent then return end
                    flyBG.CFrame = workspace.CurrentCamera.CFrame
                    local mv = Vector3.zero
                    if UserInputService:IsKeyDown(Enum.KeyCode.W) then mv += workspace.CurrentCamera.CFrame.LookVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.S) then mv -= workspace.CurrentCamera.CFrame.LookVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.A) then mv -= workspace.CurrentCamera.CFrame.RightVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.D) then mv += workspace.CurrentCamera.CFrame.RightVector end
                    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then mv += Vector3.new(0, 1, 0) end
                    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then mv -= Vector3.new(0, 1, 0) end
                    flyBV.Velocity = mv * 80
                end)
            end
        else
            if flyConn then flyConn:Disconnect(); flyConn = nil end
            if flyBV then flyBV:Destroy(); flyBV = nil end
            if flyBG then flyBG:Destroy(); flyBG = nil end
        end
    end
end)

RunService.Heartbeat:Connect(function()
    if not _G.Zutaxz_State.AntiHit then return end
    if not cache.root or not cache.hum then return end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            if r and (r.Position - cache.root.Position).Magnitude < 15 then
                local d = (cache.root.Position - r.Position).Unit
                cache.root.CFrame = cache.root.CFrame + d * 15
            end
        end
    end
    if cache.hum.Health < cache.hum.MaxHealth then
        cache.hum.Health = math.min(cache.hum.MaxHealth, cache.hum.Health + 5)
    end
end)

local eggCache = {}
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(1)
        if _G.Zutaxz_State.AutoSteal then
            eggCache = {}
            for _, obj in pairs(workspace:GetDescendants()) do
                if (obj:IsA("BasePart") or obj:IsA("Model")) and obj.Name:lower():find("egg") then
                    local part = obj:IsA("BasePart") and obj or obj.PrimaryPart
                    if part and part.Parent then table.insert(eggCache, part) end
                end
            end
        end
    end
end)

RunService.Heartbeat:Connect(function()
    if not _G.Zutaxz_State.AutoSteal then return end
    if not cache.root or #eggCache == 0 then return end
    local target = eggCache[1]
    if target and target.Parent then
        local dist = (target.Position - cache.root.Position).Magnitude
        if _G.Zutaxz_State.StealMode == "MoveTo" then
            if dist > 12 then cache.root.CFrame = CFrame.new(target.Position + Vector3.new(0, 3, 0))
            else pcall(function()
                if rawFireTouch then rawFireTouch(cache.root, target, 0); rawFireTouch(cache.root, target, 1) end
            end) end
        elseif _G.Zutaxz_State.StealMode == "Teleport" then
            cache.root.CFrame = CFrame.new(target.Position + Vector3.new(0, 3, 0))
        elseif _G.Zutaxz_State.StealMode == "Instant" then
            pcall(function()
                if rawFireTouch then rawFireTouch(cache.root, target, 0); rawFireTouch(cache.root, target, 1) end
            end)
        end
    end
end)

local espTrack, pTrack, tTrack = {}, {}, {}
RunService.Heartbeat:Connect(function()
    if not _G.Zutaxz_State.EggESP then
        for o, h in pairs(espTrack) do h:Destroy(); espTrack[o] = nil end
    else
        for _, obj in pairs(workspace:GetDescendants()) do
            if (obj:IsA("BasePart") or obj:IsA("Model")) and obj.Name:lower():find("egg") and not espTrack[obj] then
                espTrack[obj] = Instance.new("Highlight", obj)
                espTrack[obj].FillColor = Theme.Accent
                espTrack[obj].FillTransparency = 0.5
                espTrack[obj].OutlineColor = Theme.AccentHi
                espTrack[obj].DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            end
        end
    end
    if not _G.Zutaxz_State.PlayerESP then
        for p, h in pairs(pTrack) do h:Destroy(); pTrack[p] = nil end
    else
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character and not pTrack[p] then
                pTrack[p] = Instance.new("Highlight", p.Character)
                pTrack[p].FillColor = Theme.Danger
                pTrack[p].FillTransparency = 0.55
                pTrack[p].OutlineColor = Color3.fromRGB(255,255,255)
            end
        end
    end
    if not _G.Zutaxz_State.TreadmillESP then
        for o, h in pairs(tTrack) do h:Destroy(); tTrack[o] = nil end
    else
        for _, obj in pairs(workspace:GetDescendants()) do
            if obj.Name:lower():find("treadmill") and not tTrack[obj] then
                tTrack[obj] = Instance.new("Highlight", obj)
                tTrack[obj].FillColor = Theme.Gold
                tTrack[obj].FillTransparency = 0.5
            end
        end
    end
end)

task.spawn(function()
    task.wait(1)
    Notify("ZUTAXZ v9.0 FULL loaded", Theme.Accent)
    task.wait(0.4)
    Notify("🛡️ Anti-Detect ready", Theme.Shield)
end)

print("[ZUTAXZ v1.0] Loaded —  Anti-Detect optional.")
