--[[
    BananaCat Spy v3 - Remote Logger & Code Copier
    Hook pattern copy tu SimpleSpy (da test chay tren Delta)

    Cach dung:
    1. Chay script trong executor
    2. Choi game binh thuong
    3. Remote hien ben trai -> click -> xem code ben phai -> Copy
]]

-- ═══════════════════════════════════════════
-- CLEANUP
-- ═══════════════════════════════════════════
if getgenv().BananaCatSpyShutdown and type(getgenv().BananaCatSpyShutdown) == "function" then
    pcall(getgenv().BananaCatSpyShutdown)
    task.wait(0.3)
end
if getgenv().BananaCatSpyExecuted then return end

-- ═══════════════════════════════════════════
-- REFERENCES (giong SimpleSpy)
-- ═══════════════════════════════════════════
local lower = string.lower
local IsA = game.IsA
local OldDebugId = game.GetDebugId
local info = debug.info
local running = coroutine.running
local resume = coroutine.resume
local yield = coroutine.yield
local create = coroutine.create
local tspawn = task.spawn
local tdelay = task.delay

local cloneref = cloneref or function(o) return o end
local newcclosure = newcclosure or function(f) return f end
local clonefunction = clonefunction or function(f) return f end
local checkcaller = checkcaller or function() return false end
local getnamecallmethod = getnamecallmethod or function() return "" end
local getcallingscript = getcallingscript or function() return nil end
local hookfunction = hookfunction or replaceclosure
local hookmetamethod = hookmetamethod
local getrawmetatable = getrawmetatable
local setclipboard = setclipboard or toclipboard or set_clipboard or (Clipboard and Clipboard.set) or function() end

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local TweenService = cloneref(game:GetService("TweenService"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local LocalPlayer = Players.LocalPlayer

-- ═══════════════════════════════════════════
-- STORAGE (giong SimpleSpy)
-- ═══════════════════════════════════════════
local Storage = Instance.new("Folder")
local remoteEvent = Instance.new("RemoteEvent", Storage)
local remoteFunction = Instance.new("RemoteFunction", Storage)

-- Luu original TRUOC khi hook
local originalEvent = remoteEvent.FireServer
local originalFunction = remoteFunction.InvokeServer
local originalnamecall = nil

-- Syn v3 check (giong SimpleSpy)
local synv3 = false
local oth = syn and syn.oth
local unhook = oth and oth.unhook
local hook = oth and oth.hook

if syn and identifyexecutor then
    local _, version = identifyexecutor()
    if version and version:sub(1, 2) == "v3" then
        synv3 = true
    end
end

-- ═══════════════════════════════════════════
-- SCHEDULER (giong SimpleSpy - Heartbeat based)
-- ═══════════════════════════════════════════
local scheduled = {}
local spyEnabled = false
local MAX_REMOTES = 500

local function schedule(f, ...)
    table.insert(scheduled, {f, ...})
end

local function taskscheduler()
    if not spyEnabled then
        scheduled = {}
        return
    end
    if #scheduled > MAX_REMOTES + 100 then
        table.remove(scheduled, #scheduled)
    end
    if #scheduled > 0 then
        local currentf = scheduled[1]
        table.remove(scheduled, 1)
        if type(currentf) == "table" and type(currentf[1]) == "function" then
            pcall(unpack(currentf))
        end
    end
end

-- ═══════════════════════════════════════════
-- DEEP CLONE (giong SimpleSpy)
-- ═══════════════════════════════════════════
local function deepclone(args, copies)
    local copy = nil
    copies = copies or {}
    if type(args) == "table" then
        if copies[args] then
            copy = copies[args]
        else
            copy = {}
            copies[args] = copy
            for i, v in next, args do
                copy[deepclone(i, copies)] = deepclone(v, copies)
            end
        end
    elseif typeof(args) == "Instance" then
        copy = cloneref(args)
    else
        copy = args
    end
    return copy
end

local function IsCyclicTable(tbl)
    local checkedtables = {}
    local function SearchTable(t)
        table.insert(checkedtables, t)
        for i, v in next, t do
            if type(v) == "table" then
                return table.find(checkedtables, v) and true or SearchTable(v)
            end
        end
    end
    return SearchTable(tbl)
end

-- ═══════════════════════════════════════════
-- SERIALIZER
-- ═══════════════════════════════════════════
local MAX_STRING = 5000
local indent_size = 4
local getnilrequired = false

local function formatString(s)
    if #s > MAX_STRING then s = s:sub(1, MAX_STRING) end
    local r = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\t", "\\t"):gsub("\r", "\\r")
    r = r:gsub("[%c]", function(c) return "\\" .. string.byte(c) end)
    return '"' .. r .. '"'
end

local number_map = {["inf"] = "math.huge", ["-inf"] = "-math.huge", ["nan"] = "0/0"}

local function getPlayerFromInstance(inst)
    for _, p in next, Players:GetPlayers() do
        if p.Character and (inst:IsDescendantOf(p.Character) or inst == p.Character) then return p end
    end
end

local function instanceToPath(inst)
    if inst == nil then return "nil" end
    if inst == game then return "game" end
    local player = getPlayerFromInstance(inst)
    local path, current, depth = "", inst, 0
    if player then
        while current and depth < 50 do
            depth = depth + 1
            if current == player.Character then
                if player == LocalPlayer then return 'game:GetService("Players").LocalPlayer.Character' .. path
                else return instanceToPath(player) .. ".Character" .. path end
            end
            local n = current.Name
            path = (n:match("^[%a_][%w_]*$") and ("." .. n) or (':FindFirstChild("' .. n:gsub('"','\\"') .. '")')) .. path
            current = current.Parent
        end
    end
    current, path, depth = inst, "", 0
    while current and depth < 50 do
        depth = depth + 1
        if current.Parent == game then
            local ok, svc = pcall(function() return game:FindService(current.ClassName) end)
            if ok and svc then
                if current.ClassName == "Workspace" then return "workspace" .. path end
                return 'game:GetService("' .. current.ClassName .. '")' .. path
            else
                local n = current.Name
                return (n:match("^[%a_][%w_]*$") and ("game." .. n) or ('game:FindFirstChild("' .. n:gsub('"','\\"') .. '")')) .. path
            end
        elseif current.Parent == nil then
            getnilrequired = true
            return 'getNil("' .. current.Name:gsub('"','\\"') .. '", "' .. current.ClassName .. '")' .. path
        else
            local n = current.Name
            path = (n:match("^[%a_][%w_]*$") and ("." .. n) or (':WaitForChild("' .. n:gsub('"','\\"') .. '")')) .. path
        end
        current = current.Parent
    end
    return "game" .. path
end

local function valueToString(v, level, seen)
    level = level or 0
    seen = seen or {}
    local ok, t = pcall(typeof, v)
    if not ok then return '"???"' end
    if t == "number" then return number_map[tostring(v)] or tostring(v)
    elseif t == "string" then return formatString(v)
    elseif t == "boolean" then return tostring(v)
    elseif t == "nil" then return "nil"
    elseif t == "Instance" then local o2, r = pcall(instanceToPath, v); return o2 and r or tostring(v)
    elseif t == "Vector3" then return string.format("Vector3.new(%s, %s, %s)", v.X, v.Y, v.Z)
    elseif t == "Vector2" then return string.format("Vector2.new(%s, %s)", v.X, v.Y)
    elseif t == "CFrame" then
        local c = {v:GetComponents()}; local p = {}; for _,x in ipairs(c) do p[#p+1]=tostring(x) end
        return "CFrame.new(" .. table.concat(p,", ") .. ")"
    elseif t == "Color3" then return string.format("Color3.new(%s, %s, %s)", v.R, v.G, v.B)
    elseif t == "BrickColor" then return string.format("BrickColor.new(%d)", v.Number)
    elseif t == "UDim" then return string.format("UDim.new(%s, %s)", v.Scale, v.Offset)
    elseif t == "UDim2" then return string.format("UDim2.new(%s, %s, %s, %s)", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
    elseif t == "EnumItem" then return tostring(v)
    elseif t == "Enum" then return "Enum." .. tostring(v)
    elseif t == "Enums" then return "Enum"
    elseif t == "Ray" then return string.format("Ray.new(Vector3.new(%s), Vector3.new(%s))", tostring(v.Origin), tostring(v.Direction))
    elseif t == "NumberRange" then return string.format("NumberRange.new(%s, %s)", v.Min, v.Max)
    elseif t == "Rect" then return string.format("Rect.new(%s, %s, %s, %s)", v.Min.X, v.Min.Y, v.Max.X, v.Max.Y)
    elseif t == "TweenInfo" then return string.format("TweenInfo.new(%s, %s, %s, %s, %s, %s)", v.Time, tostring(v.EasingStyle), tostring(v.EasingDirection), v.RepeatCount, tostring(v.Reverses), v.DelayTime)
    elseif type(v) == "table" then
        if seen[v] then return "{} --[[circular]]" end
        seen[v] = true
        local parts, ind, cl = {}, string.rep(" ",(level+1)*indent_size), string.rep(" ",level*indent_size)
        local cnt = 0
        for k, val in next, v do
            cnt = cnt + 1
            if cnt > 300 then parts[#parts+1] = ind .. "-- ... truncated"; break end
            local ks
            if type(k) == "number" then ks = "["..tostring(k).."]"
            elseif type(k) == "string" and k:match("^[%a_][%w_]*$") then ks = k
            else ks = "["..valueToString(k,level+1,seen).."]" end
            parts[#parts+1] = ind .. ks .. " = " .. valueToString(val,level+1,seen)
        end
        seen[v] = nil
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts,",\n") .. "\n" .. cl .. "}"
    elseif type(v) == "function" then return "function() end --[[function]]"
    else return tostring(v) .. " --[[" .. t .. "]]" end
end

local function generateCode(remote, args)
    getnilrequired = false
    local rp = instanceToPath(remote)
    local isEv = remote:IsA("RemoteEvent")
    if args and #args > 0 then
        local code = "local args = " .. valueToString(args, 0) .. "\n\n"
        if getnilrequired then
            code = "function getNil(name,class) for _,v in next,getnilinstances() do if v.ClassName==class and v.Name==name then return v end end end\n\n" .. code
        end
        return code .. rp .. (isEv and ":FireServer(unpack(args))" or ":InvokeServer(unpack(args))")
    else
        return rp .. (isEv and ":FireServer()" or ":InvokeServer()")
    end
end

-- ═══════════════════════════════════════════
-- GUI
-- ═══════════════════════════════════════════
local gui = Instance.new("ScreenGui")
gui.Name = "BananaCatSpy"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local main = Instance.new("Frame")
main.Name = "Main"; main.Parent = gui
main.BackgroundColor3 = Color3.fromRGB(25,25,30); main.BorderSizePixel = 0
main.Position = UDim2.new(0,100,0,100); main.Size = UDim2.new(0,550,0,320)
main.ClipsDescendants = true
Instance.new("UICorner",main).CornerRadius = UDim.new(0,8)

local titleBar = Instance.new("Frame")
titleBar.Parent = main; titleBar.BackgroundColor3 = Color3.fromRGB(18,18,22)
titleBar.BorderSizePixel = 0; titleBar.Size = UDim2.new(1,0,0,28)
Instance.new("UICorner",titleBar).CornerRadius = UDim.new(0,8)
local tFix = Instance.new("Frame"); tFix.Parent = titleBar
tFix.BackgroundColor3 = Color3.fromRGB(18,18,22); tFix.BorderSizePixel = 0
tFix.Position = UDim2.new(0,0,1,-8); tFix.Size = UDim2.new(1,0,0,8)

local titleText = Instance.new("TextLabel"); titleText.Parent = titleBar
titleText.BackgroundTransparency = 1; titleText.Position = UDim2.new(0,10,0,0)
titleText.Size = UDim2.new(0,150,1,0); titleText.Font = Enum.Font.GothamBold
titleText.Text = "BananaCat Spy"; titleText.TextColor3 = Color3.fromRGB(255,200,60)
titleText.TextSize = 13; titleText.TextXAlignment = Enum.TextXAlignment.Left

local statusLabel = Instance.new("TextLabel"); statusLabel.Parent = titleBar
statusLabel.BackgroundTransparency = 1; statusLabel.Position = UDim2.new(0.28,0,0,0)
statusLabel.Size = UDim2.new(0.35,0,1,0); statusLabel.Font = Enum.Font.Gotham
statusLabel.Text = "Loading..."; statusLabel.TextColor3 = Color3.fromRGB(255,200,60)
statusLabel.TextSize = 11

local counterLabel = Instance.new("TextLabel"); counterLabel.Parent = titleBar
counterLabel.BackgroundTransparency = 1; counterLabel.Position = UDim2.new(0.63,0,0,0)
counterLabel.Size = UDim2.new(0.12,0,1,0); counterLabel.Font = Enum.Font.GothamBold
counterLabel.Text = "0"; counterLabel.TextColor3 = Color3.fromRGB(200,200,200)
counterLabel.TextSize = 11

local function mkBtn(par,pos,txt,col)
    local b = Instance.new("TextButton"); b.Parent = par
    b.BackgroundColor3 = Color3.fromRGB(40,40,50); b.BorderSizePixel = 0
    b.Position = pos; b.Size = UDim2.new(0,22,0,22)
    b.Font = Enum.Font.GothamBold; b.Text = txt; b.TextColor3 = col
    b.TextSize = 12; b.AutoButtonColor = false
    Instance.new("UICorner",b).CornerRadius = UDim.new(0,4)
    return b
end
local toggleBtn = mkBtn(titleBar,UDim2.new(1,-90,0,3),"II",Color3.new(1,1,1))
local minBtn = mkBtn(titleBar,UDim2.new(1,-62,0,3),"-",Color3.fromRGB(255,200,60))
local closeBtn = mkBtn(titleBar,UDim2.new(1,-34,0,3),"X",Color3.fromRGB(255,80,80))

local leftPanel = Instance.new("Frame"); leftPanel.Parent = main
leftPanel.BackgroundColor3 = Color3.fromRGB(30,30,38); leftPanel.BorderSizePixel = 0
leftPanel.Position = UDim2.new(0,0,0,28); leftPanel.Size = UDim2.new(0,170,1,-28)

local remoteList = Instance.new("ScrollingFrame"); remoteList.Parent = leftPanel
remoteList.BackgroundTransparency = 1; remoteList.Position = UDim2.new(0,0,0,5)
remoteList.Size = UDim2.new(1,0,1,-68); remoteList.CanvasSize = UDim2.new(0,0,0,0)
remoteList.ScrollBarThickness = 3; remoteList.ScrollBarImageColor3 = Color3.fromRGB(255,200,60)
remoteList.AutomaticCanvasSize = Enum.AutomaticSize.Y
local ll = Instance.new("UIListLayout"); ll.Parent = remoteList
ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Padding = UDim.new(0,2)
ll.HorizontalAlignment = Enum.HorizontalAlignment.Center

-- NUT SAVE GAME (saveinstance) - to, noi bat
local saveGameBtn = Instance.new("TextButton"); saveGameBtn.Parent = leftPanel
saveGameBtn.BackgroundColor3 = Color3.fromRGB(180,60,200); saveGameBtn.BorderSizePixel = 0
saveGameBtn.Position = UDim2.new(0,5,1,-62); saveGameBtn.Size = UDim2.new(1,-10,0,27)
saveGameBtn.Font = Enum.Font.GothamBold; saveGameBtn.Text = "SAVE GAME"
saveGameBtn.TextColor3 = Color3.new(1,1,1); saveGameBtn.TextSize = 12
saveGameBtn.AutoButtonColor = false; Instance.new("UICorner",saveGameBtn).CornerRadius = UDim.new(0,4)

local clearBtn = Instance.new("TextButton"); clearBtn.Parent = leftPanel
clearBtn.BackgroundColor3 = Color3.fromRGB(60,40,40); clearBtn.BorderSizePixel = 0
clearBtn.Position = UDim2.new(0,5,1,-32); clearBtn.Size = UDim2.new(1,-10,0,27)
clearBtn.Font = Enum.Font.GothamBold; clearBtn.Text = "Xoa Logs"
clearBtn.TextColor3 = Color3.fromRGB(255,120,120); clearBtn.TextSize = 11
clearBtn.AutoButtonColor = false; Instance.new("UICorner",clearBtn).CornerRadius = UDim.new(0,4)

local rightPanel = Instance.new("Frame"); rightPanel.Parent = main
rightPanel.BackgroundColor3 = Color3.fromRGB(20,20,25); rightPanel.BorderSizePixel = 0
rightPanel.Position = UDim2.new(0,170,0,28); rightPanel.Size = UDim2.new(1,-170,1,-28)

local infoBar = Instance.new("Frame"); infoBar.Parent = rightPanel
infoBar.BackgroundColor3 = Color3.fromRGB(28,28,35); infoBar.BorderSizePixel = 0
infoBar.Size = UDim2.new(1,0,0,52)

local infoText = Instance.new("TextLabel"); infoText.Parent = infoBar
infoText.BackgroundTransparency = 1; infoText.Position = UDim2.new(0,8,0,0)
infoText.Size = UDim2.new(0.45,0,0,26); infoText.Font = Enum.Font.Gotham
infoText.Text = "Click remote de xem code"; infoText.TextColor3 = Color3.fromRGB(150,150,160)
infoText.TextSize = 11; infoText.TextXAlignment = Enum.TextXAlignment.Left

-- Row 1: Copy 1 remote
local copyBtn = Instance.new("TextButton"); copyBtn.Parent = infoBar
copyBtn.BackgroundColor3 = Color3.fromRGB(60,130,60); copyBtn.BorderSizePixel = 0
copyBtn.Position = UDim2.new(1,-70,0,3); copyBtn.Size = UDim2.new(0,65,0,22)
copyBtn.Font = Enum.Font.GothamBold; copyBtn.Text = "Copy 1"
copyBtn.TextColor3 = Color3.new(1,1,1); copyBtn.TextSize = 11; copyBtn.AutoButtonColor = false
Instance.new("UICorner",copyBtn).CornerRadius = UDim.new(0,4)

-- Row 2: COPY ALL + SAVE FILE (to noi bat)
local copyAllBtn = Instance.new("TextButton"); copyAllBtn.Parent = infoBar
copyAllBtn.BackgroundColor3 = Color3.fromRGB(200,140,30); copyAllBtn.BorderSizePixel = 0
copyAllBtn.Position = UDim2.new(0,5,0,27); copyAllBtn.Size = UDim2.new(0.48,-8,0,22)
copyAllBtn.Font = Enum.Font.GothamBold; copyAllBtn.Text = "COPY TAT CA"
copyAllBtn.TextColor3 = Color3.fromRGB(0,0,0); copyAllBtn.TextSize = 12; copyAllBtn.AutoButtonColor = false
Instance.new("UICorner",copyAllBtn).CornerRadius = UDim.new(0,4)

local saveFileBtn = Instance.new("TextButton"); saveFileBtn.Parent = infoBar
saveFileBtn.BackgroundColor3 = Color3.fromRGB(50,120,180); saveFileBtn.BorderSizePixel = 0
saveFileBtn.Position = UDim2.new(0.48,2,0,27); saveFileBtn.Size = UDim2.new(0.52,-7,0,22)
saveFileBtn.Font = Enum.Font.GothamBold; saveFileBtn.Text = "LUU FILE (.lua)"
saveFileBtn.TextColor3 = Color3.new(1,1,1); saveFileBtn.TextSize = 12; saveFileBtn.AutoButtonColor = false
Instance.new("UICorner",saveFileBtn).CornerRadius = UDim.new(0,4)

local codeScroll = Instance.new("ScrollingFrame"); codeScroll.Parent = rightPanel
codeScroll.BackgroundColor3 = Color3.fromRGB(15,15,18); codeScroll.BorderSizePixel = 0
codeScroll.Position = UDim2.new(0,0,0,52); codeScroll.Size = UDim2.new(1,0,1,-52)
codeScroll.CanvasSize = UDim2.new(0,0,0,0); codeScroll.ScrollBarThickness = 4
codeScroll.ScrollBarImageColor3 = Color3.fromRGB(100,100,120)
codeScroll.AutomaticCanvasSize = Enum.AutomaticSize.XY

local codeLabel = Instance.new("TextLabel"); codeLabel.Parent = codeScroll
codeLabel.BackgroundTransparency = 1; codeLabel.Position = UDim2.new(0,8,0,5)
codeLabel.Size = UDim2.new(1,-16,0,0); codeLabel.AutomaticSize = Enum.AutomaticSize.XY
codeLabel.Font = Enum.Font.Code; codeLabel.TextColor3 = Color3.fromRGB(200,200,210)
codeLabel.TextSize = 13; codeLabel.TextXAlignment = Enum.TextXAlignment.Left
codeLabel.TextYAlignment = Enum.TextYAlignment.Top; codeLabel.TextWrapped = false
codeLabel.RichText = false
codeLabel.Text = "-- Dang load hooks...\n-- Doi 1 chut..."

-- ═══════════════════════════════════════════
-- DRAG
-- ═══════════════════════════════════════════
local dragging, dragStart, startPos = false, nil, nil
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        local mp = UserInputService:GetMouseLocation()
        if mp.X - titleBar.AbsolutePosition.X > titleBar.AbsoluteSize.X - 100 then return end
        dragging = true; dragStart = input.Position; startPos = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
    end
end)

-- ═══════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════
local logs = {}
local remoteLogs = {}
local selectedLog, selectedBtn = nil, nil
local paused = false
local layoutOrder = 999999
local totalCount = 0
local minimized, originalSize = false, nil

-- ═══════════════════════════════════════════
-- LOG ENTRY
-- ═══════════════════════════════════════════
local function selectRemote(logEntry, button)
    if selectedBtn then
        pcall(function() TweenService:Create(selectedBtn, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(38,38,48)}):Play() end)
    end
    selectedLog = logEntry; selectedBtn = button
    pcall(function() TweenService:Create(button, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(60,60,100)}):Play() end)
    local ok, code = pcall(generateCode, logEntry.Remote, logEntry.Args)
    if not ok then code = "-- Error: " .. tostring(code) end
    local meta = "-- Remote: " .. (pcall(function() return logEntry.Remote:GetFullName() end) and logEntry.Remote:GetFullName() or logEntry.Remote.Name)
    meta = meta .. "\n-- Type: " .. (logEntry.Remote:IsA("RemoteEvent") and "RemoteEvent" or "RemoteFunction")
    meta = meta .. "\n-- Method: " .. logEntry.Method
    if logEntry.Source then meta = meta .. "\n-- Script: " .. tostring(logEntry.Source) end
    meta = meta .. "\n-- Time: " .. logEntry.Time .. "\n\n"
    logEntry.Code = meta .. code
    codeLabel.Text = logEntry.Code
    infoText.Text = logEntry.Remote.Name .. " (" .. (logEntry.Remote:IsA("RemoteEvent") and "E" or "F") .. ")"
end

local function addRemoteLog(remote, args, method, source)
    if paused then return end
    if layoutOrder < 1 then layoutOrder = 999999 end
    totalCount = totalCount + 1
    counterLabel.Text = tostring(totalCount)
    local ts = os.date("%H:%M:%S")
    local ca = {}; pcall(function() ca = deepclone(args) end)
    local entry = {Remote=remote, Args=ca, Method=method, Source=source, Time=ts, Code=nil}

    local btn = Instance.new("TextButton"); btn.Parent = remoteList
    btn.BackgroundColor3 = Color3.fromRGB(38,38,48); btn.BorderSizePixel = 0
    btn.Size = UDim2.new(1,-6,0,26); btn.Font = Enum.Font.Gotham; btn.TextSize = 11
    btn.TextColor3 = Color3.fromRGB(220,220,220); btn.TextTruncate = Enum.TextTruncate.AtEnd
    btn.TextXAlignment = Enum.TextXAlignment.Left; btn.AutoButtonColor = false
    btn.LayoutOrder = layoutOrder; btn.Text = ""
    Instance.new("UICorner",btn).CornerRadius = UDim.new(0,4)

    local cb = Instance.new("Frame"); cb.Parent = btn
    cb.BackgroundColor3 = remote:IsA("RemoteEvent") and Color3.fromRGB(255,200,50) or Color3.fromRGB(100,80,255)
    cb.BorderSizePixel = 0; cb.Size = UDim2.new(0,3,1,0)

    local nl = Instance.new("TextLabel"); nl.Parent = btn; nl.BackgroundTransparency = 1
    nl.Position = UDim2.new(0,8,0,0); nl.Size = UDim2.new(1,-50,0.5,0)
    nl.Font = Enum.Font.GothamBold; nl.Text = remote.Name
    nl.TextColor3 = Color3.fromRGB(230,230,240); nl.TextSize = 10
    nl.TextXAlignment = Enum.TextXAlignment.Left; nl.TextTruncate = Enum.TextTruncate.AtEnd

    local tl = Instance.new("TextLabel"); tl.Parent = btn; tl.BackgroundTransparency = 1
    tl.Position = UDim2.new(1,-42,0,0); tl.Size = UDim2.new(0,40,0.5,0)
    tl.Font = Enum.Font.Gotham; tl.Text = ts
    tl.TextColor3 = Color3.fromRGB(120,120,130); tl.TextSize = 9
    tl.TextXAlignment = Enum.TextXAlignment.Right

    local al = Instance.new("TextLabel"); al.Parent = btn; al.BackgroundTransparency = 1
    al.Position = UDim2.new(0,8,0.5,0); al.Size = UDim2.new(1,-16,0.5,0)
    al.Font = Enum.Font.Gotham; al.TextSize = 9; al.TextXAlignment = Enum.TextXAlignment.Left
    al.Text = (remote:IsA("RemoteEvent") and "Event" or "Func") .. " | " .. #args .. " args"
    al.TextColor3 = Color3.fromRGB(140,140,150)

    btn.MouseButton1Click:Connect(function() selectRemote(entry, btn) end)
    btn.MouseEnter:Connect(function()
        if selectedBtn ~= btn then pcall(function() TweenService:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(48,48,60)}):Play() end) end
    end)
    btn.MouseLeave:Connect(function()
        if selectedBtn ~= btn then pcall(function() TweenService:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(38,38,48)}):Play() end) end
    end)

    table.insert(remoteLogs, 1, {entry=entry, button=btn})
    layoutOrder = layoutOrder - 1

    while #remoteLogs > MAX_REMOTES do
        local old = table.remove(remoteLogs)
        if old and old.button then old.button:Destroy() end
    end
end

-- ═══════════════════════════════════════════
-- REMOTE HANDLER (goi boi scheduler)
-- ═══════════════════════════════════════════
local function remoteHandler(data)
    if data.remote:IsA("RemoteEvent") and lower(data.method) == "fireserver" then
        addRemoteLog(data.remote, data.args, data.method, data.callingscript)
    elseif data.remote:IsA("RemoteFunction") and lower(data.method) == "invokeserver" then
        addRemoteLog(data.remote, data.args, data.method, data.callingscript)
    end
end

-- ═══════════════════════════════════════════
-- HOOKS (COPY CHINH XAC TU SIMPLESPY)
-- ═══════════════════════════════════════════

-- newindex handler cho FireServer/InvokeServer hooks
-- GIONG SimpleSpy: function(method, originalfunction, ...)
-- ... bao gom self (remote) + args
local newindex = function(method, originalfunction, ...)
    if typeof(...) == "Instance" then
        local remote = cloneref(...)

        if remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") then
            if checkcaller() then return originalfunction(...) end
            local args = {select(2, ...)}

            if not IsCyclicTable(args) then
                local data = {
                    method = method,
                    remote = remote,
                    args = deepclone(args),
                    callingscript = nil,
                }
                args = nil

                pcall(function()
                    local calling = getcallingscript()
                    data.callingscript = calling and cloneref(calling) or nil
                end)

                schedule(remoteHandler, data)
            end
        end
    end
    return originalfunction(...)
end

-- __namecall hook
-- GIONG SimpleSpy: newcclosure(function(...))
local newnamecall = newcclosure(function(...)
    local method = getnamecallmethod()

    if method and (method == "FireServer" or method == "fireServer" or method == "InvokeServer" or method == "invokeServer") then
        if typeof(...) == "Instance" then
            local remote = cloneref(...)

            if IsA(remote, "RemoteEvent") or IsA(remote, "RemoteFunction") then
                if checkcaller() then return originalnamecall(...) end
                local args = {select(2, ...)}

                if not IsCyclicTable(args) then
                    local data = {
                        method = method,
                        remote = remote,
                        args = deepclone(args),
                        callingscript = nil,
                    }
                    args = nil

                    pcall(function()
                        local calling = getcallingscript()
                        data.callingscript = calling and cloneref(calling) or nil
                    end)

                    schedule(remoteHandler, data)
                end
            end
        end
    end
    return originalnamecall(...)
end)

-- FireServer/InvokeServer hooks
-- GIONG SimpleSpy: newcclosure(function(...) return newindex(method, original, ...) end)
local newFireServer = newcclosure(function(...)
    return newindex("FireServer", originalEvent, ...)
end)

local newInvokeServer = newcclosure(function(...)
    return newindex("InvokeServer", originalFunction, ...)
end)

-- ═══════════════════════════════════════════
-- ENABLE/DISABLE HOOKS (GIONG SimpleSpy)
-- ═══════════════════════════════════════════
local schedulerconnect = nil

local function disablehooks()
    pcall(function()
        if synv3 then
            unhook(getrawmetatable(game).__namecall, originalnamecall)
            unhook(Instance.new("RemoteEvent").FireServer, originalEvent)
            unhook(Instance.new("RemoteFunction").InvokeServer, originalFunction)
            restorefunction(originalnamecall)
            restorefunction(originalEvent)
            restorefunction(originalFunction)
        else
            if hookmetamethod then
                hookmetamethod(game, "__namecall", originalnamecall)
            elseif hookfunction and getrawmetatable then
                hookfunction(getrawmetatable(game).__namecall, originalnamecall)
            end
            if hookfunction then
                hookfunction(Instance.new("RemoteEvent").FireServer, originalEvent)
                hookfunction(Instance.new("RemoteFunction").InvokeServer, originalFunction)
            end
        end
    end)
end

local function enablehooks()
    local oldnamecall
    local hookStatus = {namecall = false, fire = false, invoke = false}

    if synv3 then
        pcall(function()
            oldnamecall = hook(getrawmetatable(game).__namecall, clonefunction(newnamecall))
            hookStatus.namecall = true
        end)
        pcall(function()
            originalEvent = hook(Instance.new("RemoteEvent").FireServer, clonefunction(newFireServer))
            hookStatus.fire = true
        end)
        pcall(function()
            originalFunction = hook(Instance.new("RemoteFunction").InvokeServer, clonefunction(newInvokeServer))
            hookStatus.invoke = true
        end)
    else
        -- __namecall hook
        pcall(function()
            if hookmetamethod then
                oldnamecall = hookmetamethod(game, "__namecall", clonefunction(newnamecall))
                hookStatus.namecall = true
            elseif hookfunction and getrawmetatable then
                oldnamecall = hookfunction(getrawmetatable(game).__namecall, clonefunction(newnamecall))
                hookStatus.namecall = true
            end
        end)

        -- FireServer hook
        pcall(function()
            if hookfunction then
                originalEvent = hookfunction(Instance.new("RemoteEvent").FireServer, clonefunction(newFireServer))
                hookStatus.fire = true
            end
        end)

        -- InvokeServer hook
        pcall(function()
            if hookfunction then
                originalFunction = hookfunction(Instance.new("RemoteFunction").InvokeServer, clonefunction(newInvokeServer))
                hookStatus.invoke = true
            end
        end)
    end

    -- Wrap originalnamecall (GIONG SimpleSpy)
    originalnamecall = originalnamecall or function(...)
        return oldnamecall(...)
    end

    spyEnabled = true

    -- Show status
    local s = "-- BananaCat Spy v3 - Hook Status:\n"
    s = s .. "-- __namecall: " .. (hookStatus.namecall and "OK" or "FAILED") .. "\n"
    s = s .. "-- FireServer: " .. (hookStatus.fire and "OK" or "FAILED") .. "\n"
    s = s .. "-- InvokeServer: " .. (hookStatus.invoke and "OK" or "FAILED") .. "\n"
    s = s .. "--\n-- Choi game binh thuong, remote se hien ben trai!\n-- Click remote -> xem code -> bam Copy"
    codeLabel.Text = s

    local anyOk = hookStatus.namecall or hookStatus.fire or hookStatus.invoke
    if anyOk then
        statusLabel.Text = "Dang bat remotes..."
        statusLabel.TextColor3 = Color3.fromRGB(80,255,80)
    else
        statusLabel.Text = "HOOK FAILED"
        statusLabel.TextColor3 = Color3.fromRGB(255,80,80)
    end

    return anyOk
end

-- ═══════════════════════════════════════════
-- BUTTON HANDLERS
-- ═══════════════════════════════════════════
copyBtn.MouseButton1Click:Connect(function()
    if selectedLog and selectedLog.Code then
        pcall(setclipboard, selectedLog.Code)
        copyBtn.Text = "OK!"; copyBtn.BackgroundColor3 = Color3.fromRGB(40,160,40)
        tdelay(1.5, function() copyBtn.Text = "Copy 1"; copyBtn.BackgroundColor3 = Color3.fromRGB(60,130,60) end)
    end
end)

-- Tao noi dung ALL (dung chung cho Copy All va Save File)
local function buildAllCode()
    if #remoteLogs == 0 then return nil, 0 end
    local blocks = {}
    local total = #remoteLogs
    for i, log in ipairs(remoteLogs) do
        local remoteName = "?"
        pcall(function() remoteName = log.entry.Remote.Name end)
        local remoteType = "?"
        pcall(function() remoteType = log.entry.Remote:IsA("RemoteEvent") and "Event" or "Function" end)
        local ok2, code = pcall(generateCode, log.entry.Remote, log.entry.Args)
        local header = "-- [" .. i .. "/" .. total .. "] " .. remoteName .. " (" .. remoteType .. ")"
        if log.entry.Source then
            header = header .. " | Script: " .. tostring(log.entry.Source)
        end
        header = header .. " | " .. (log.entry.Time or "?")
        blocks[#blocks+1] = header .. "\n" .. (ok2 and code or "-- error generating code")
    end
    local all = "-- ═══════════════════════════════════════════\n"
    all = all .. "-- BananaCat Spy - TAT CA " .. total .. " remote calls\n"
    all = all .. "-- Thoi gian export: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n"
    all = all .. "-- ═══════════════════════════════════════════\n\n"
    all = all .. table.concat(blocks, "\n\n-- ─────────────────────────────────────\n\n")
    return all, total
end

-- COPY TAT CA (moi lan goi, ke ca trung)
copyAllBtn.MouseButton1Click:Connect(function()
    local all, total = buildAllCode()
    if not all then return end
    pcall(setclipboard, all)
    copyAllBtn.Text = "DA COPY " .. total .. "!"
    copyAllBtn.BackgroundColor3 = Color3.fromRGB(40,160,40)
    codeLabel.Text = all -- hien luon trong code box de xem
    infoText.Text = "Da copy " .. total .. " remote calls"
    tdelay(2, function()
        copyAllBtn.Text = "COPY TAT CA"
        copyAllBtn.BackgroundColor3 = Color3.fromRGB(200,140,30)
    end)
end)

-- LUU FILE (writefile vao executor workspace)
saveFileBtn.MouseButton1Click:Connect(function()
    local all, total = buildAllCode()
    if not all then return end
    local filename = "BananaCatSpy_" .. os.date("%H%M%S") .. ".lua"
    local saved = false
    pcall(function()
        if writefile then
            writefile(filename, all)
            saved = true
        end
    end)
    if saved then
        saveFileBtn.Text = "DA LUU!"
        saveFileBtn.BackgroundColor3 = Color3.fromRGB(40,160,40)
        infoText.Text = "File: " .. filename .. " (" .. total .. " calls)"
        codeLabel.Text = "-- Da luu " .. total .. " remote calls vao file:\n-- " .. filename .. "\n--\n-- Tim file trong thu muc workspace cua executor\n-- (vd: Delta/workspace/" .. filename .. ")\n\n" .. all
    else
        -- Fallback: copy vao clipboard neu khong co writefile
        pcall(setclipboard, all)
        saveFileBtn.Text = "COPIED!"
        saveFileBtn.BackgroundColor3 = Color3.fromRGB(200,140,30)
        infoText.Text = "writefile khong co, da copy clipboard"
        codeLabel.Text = "-- Executor khong ho tro writefile\n-- Da copy " .. total .. " calls vao clipboard thay the\n\n" .. all
    end
    tdelay(2, function()
        saveFileBtn.Text = "LUU FILE (.lua)"
        saveFileBtn.BackgroundColor3 = Color3.fromRGB(50,120,180)
    end)
end)

clearBtn.MouseButton1Click:Connect(function()
    for _, l in ipairs(remoteLogs) do if l.button then l.button:Destroy() end end
    remoteLogs = {}; selectedLog = nil; selectedBtn = nil; totalCount = 0
    counterLabel.Text = "0"; codeLabel.Text = "-- Logs da xoa"
    infoText.Text = "Click remote de xem code"
end)

toggleBtn.MouseButton1Click:Connect(function()
    paused = not paused
    if paused then
        toggleBtn.Text = ">"; statusLabel.Text = "Tam dung"; statusLabel.TextColor3 = Color3.fromRGB(255,200,60)
    else
        toggleBtn.Text = "II"; statusLabel.Text = "Dang bat remotes..."; statusLabel.TextColor3 = Color3.fromRGB(80,255,80)
    end
end)

-- SAVE GAME (saveinstance - luu het game gom ModuleScript, LocalScript, GUI, Map)
saveGameBtn.MouseButton1Click:Connect(function()
    saveGameBtn.Text = "DANG LUU..."
    saveGameBtn.BackgroundColor3 = Color3.fromRGB(255,200,60)
    saveGameBtn.TextColor3 = Color3.fromRGB(0,0,0)
    infoText.Text = "Dang saveinstance..."
    codeLabel.Text = "-- SAVE GAME dang chay...\n-- Doi 1 chut, game co the lag nhe\n--\n-- Se luu tat ca:\n--   ModuleScript (code game)\n--   LocalScript (client code)\n--   GUI (giao dien)\n--   Map (workspace)\n--   Assets"

    tdelay(0.2, function()
        local ok, err = pcall(function()
            if saveinstance then
                saveinstance({
                    mode = "optimized",
                    noscripts = false,
                    scriptcache = true,
                    timeout = 30,
                })
            elseif syn and syn.saveinstance then
                syn.saveinstance()
            else
                error("saveinstance not found")
            end
        end)

        if ok then
            saveGameBtn.Text = "DA LUU!"
            saveGameBtn.BackgroundColor3 = Color3.fromRGB(40,180,40)
            saveGameBtn.TextColor3 = Color3.new(1,1,1)
            local gameName = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name or "Game"
            infoText.Text = "Da luu: " .. gameName
            codeLabel.Text = "-- SAVE GAME THANH CONG!\n--\n-- File .rbxl da luu trong:\n--   Delta/workspace/\n--   hoac Synapse/workspace/\n--\n-- Mo file bang Roblox Studio de xem:\n--   - Tat ca ModuleScript (code game)\n--   - Tat ca LocalScript (client scripts)\n--   - GUI (giao dien)\n--   - Map (workspace, models)\n--   - ReplicatedStorage, StarterPack...\n--\n-- Cach dung:\n-- 1. Mo Roblox Studio\n-- 2. File > Open > chon file .rbxl\n-- 3. Explorer panel > tim script can xem\n-- 4. Double-click script de xem code"
        else
            saveGameBtn.Text = "LOI!"
            saveGameBtn.BackgroundColor3 = Color3.fromRGB(255,60,60)
            saveGameBtn.TextColor3 = Color3.new(1,1,1)
            infoText.Text = "saveinstance failed"
            codeLabel.Text = "-- LOI: Khong the saveinstance\n-- " .. tostring(err) .. "\n--\n-- Thu cach khac:\n-- 1. Chay truc tiep: saveinstance()\n-- 2. Hoac dung Infinite Yield: saveinstance\n-- 3. Kiem tra executor co ho tro saveinstance khong"
        end

        tdelay(3, function()
            saveGameBtn.Text = "SAVE GAME"
            saveGameBtn.BackgroundColor3 = Color3.fromRGB(180,60,200)
            saveGameBtn.TextColor3 = Color3.new(1,1,1)
        end)
    end)
end)

minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        originalSize = main.Size
        TweenService:Create(main,TweenInfo.new(0.3,Enum.EasingStyle.Quad),{Size=UDim2.new(0,550,0,28)}):Play()
    else
        TweenService:Create(main,TweenInfo.new(0.3,Enum.EasingStyle.Quad),{Size=originalSize or UDim2.new(0,550,0,320)}):Play()
    end
end)

local function shutdown()
    spyEnabled = false
    if schedulerconnect then schedulerconnect:Disconnect() end
    disablehooks()
    gui:Destroy()
    Storage:Destroy()
    getgenv().BananaCatSpyExecuted = false
    getgenv().BananaCatSpyShutdown = nil
end

closeBtn.MouseButton1Click:Connect(shutdown)

-- ═══════════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════════
getgenv().BananaCatSpyExecuted = true
getgenv().BananaCatSpyShutdown = shutdown

-- Parent GUI (giong SimpleSpy)
gui.Parent = (gethui and gethui()) or (syn and syn.protect_gui and syn.protect_gui(gui)) or CoreGui

-- Enable hooks (giong SimpleSpy: goi 1 lan)
enablehooks()

-- Connect scheduler (GIONG SimpleSpy: Heartbeat)
schedulerconnect = RunService.Heartbeat:Connect(taskscheduler)

warn("[BananaCat Spy v3] Da bat thanh cong!")
