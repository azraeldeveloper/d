---@diagnostic disable: undefined-global, duplicate-index, deprecated, unused-local
local Functions = {}
local Services = {
    SPlayers          = game:GetService("Players"),
    SRunService       = game:GetService("RunService"),
    SUserInputService = game:GetService("UserInputService"),
    STweenService     = game:GetService("TweenService"),
    SLighting         = game:GetService("Lighting"),
    SCoreGui          = game:GetService("CoreGui"),
    STeleportService  = game:GetService("TeleportService"),
    SHttpService      = game:GetService("HttpService"),
}

local Camera      = workspace.CurrentCamera
local LocalPlayer = Services.SPlayers.LocalPlayer
local SharedRaycast = RaycastParams.new()
SharedRaycast.FilterType = Enum.RaycastFilterType.Blacklist
local coreParts = { "Head", "HumanoidRootPart", "UpperTorso", "Torso" }
local _visCache = {}
local _VIS_TTL  = 0.1

function Functions:Notify(msg, timer, Library)
    if Library and Library.Notify then
        pcall(function()
            Library:Notify({ Title = "Notification", Description = "[Deproxware] " .. tostring(msg), Time = timer or 3 })
        end)
    else
        print("[Deproxware] " .. tostring(msg))
    end
end

function Functions:IsProtected(player, protectedList)
    if not player then return false end
    if type(protectedList) ~= "table" or #protectedList == 0 then return false end
    local pName = string.lower(player.Name)
    local pId   = player.UserId
    for i = 1, #protectedList do
        local entry = protectedList[i]
        if typeof(entry) == "string" and string.lower(entry) == pName then return true
        elseif typeof(entry) == "number" and pId == entry then return true end
    end
    return false
end

function Functions:TeamCheck(targetPlayer, settings)
    settings = settings or {}
    if not settings.TeamCheckEnabled then return true end
    local myTeam    = LocalPlayer and LocalPlayer.Team
    local theirTeam = targetPlayer and targetPlayer.Team

    if type(settings.ExcludedTeams) == "table" and #settings.ExcludedTeams > 0 and theirTeam then
        local tName = string.lower(theirTeam.Name)
        for i = 1, #settings.ExcludedTeams do
            if string.lower(tostring(settings.ExcludedTeams[i])) == tName then return false end
        end
    end

    if not myTeam or not theirTeam then return true end
    return theirTeam ~= myTeam
end

function Functions:IsVisible(player)
    if not player or not player.Character or not player.Character.Parent then return false end

    local now   = tick()
    local entry = _visCache[player]
    if entry and (now - entry.t) < _VIS_TTL then return entry.result end

    local camCF = Camera and Camera.CFrame
    if not camCF then return false end
    local camPos = camCF.Position

    if LocalPlayer.Character then
        SharedRaycast.FilterDescendantsInstances = { LocalPlayer.Character }
    end

    local char   = player.Character
    local result = false
    for i = 1, #coreParts do
        local part = char:FindFirstChild(coreParts[i])
        if part and part:IsA("BasePart") then
            local pp = part.Position
            local dx, dy, dz = pp.X - camPos.X, pp.Y - camPos.Y, pp.Z - camPos.Z
            local mag = math.sqrt(dx*dx + dy*dy + dz*dz)
            if mag > 0 then
                local rayLen = math.min(1000, mag + 0.1)
                local inv    = rayLen / mag
                local hit    = workspace:Raycast(camPos, Vector3.new(dx*inv, dy*inv, dz*inv), SharedRaycast)
                if hit and hit.Instance and hit.Instance:IsDescendantOf(char) then
                    result = true
                    break
                end
            end
        end
    end

    _visCache[player] = { result = result, t = now }
    return result
end

Services.SPlayers.PlayerRemoving:Connect(function(p)
    _visCache[p] = nil
end)

function Functions:Teleport(targetPos, settings, Library)
    settings = settings or {}
    local char  = LocalPlayer.Character
    local hrp   = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local destination = CFrame.new(targetPos) + Vector3.new(0, 3, 0)
    local method      = settings.TeleportMethod or "Instant"

    if method == "Instant" then
        if workspace.StreamingEnabled then
            pcall(function() LocalPlayer:RequestStreamAroundAsync(targetPos) end)
        end
        hrp.CFrame = destination
        self:Notify("Teleported Instantly", 3, Library)

    elseif method == "Tween" then
        local speed    = math.max(1, settings.TeleportSpeed or 50)
        local distance = (hrp.Position - targetPos).Magnitude
        local duration = distance / speed

        local tweenParts = {}
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then tweenParts[#tweenParts+1] = part end
        end

        local tempConn = Services.SRunService.Stepped:Connect(function()
            for _, part in ipairs(tweenParts) do
                part.CanCollide = false
            end
        end)

        hrp.Anchored = true
        local tween  = Services.STweenService:Create(
            hrp,
            TweenInfo.new(duration, Enum.EasingStyle.Linear),
            { CFrame = destination }
        )
        tween:Play()
        self:Notify("Tweening... " .. math.floor(duration) .. "s remaining", 3, Library)

        tween.Completed:Connect(function()
            hrp.Anchored = false
            hrp.Velocity = Vector3.zero
            if not (settings.Noclip) then
                tempConn:Disconnect()
            end
        end)
    end
end

function Functions:Pathfind(targetPosition, Library)
    local PathfindingService = game:GetService("PathfindingService")
    local char     = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local root     = char and char:FindFirstChild("HumanoidRootPart")
    if not root or not humanoid then return end

    if workspace:FindFirstChild("PathVisuals") then
        workspace.PathVisuals:Destroy()
    end
    local pathFolder = Instance.new("Folder", workspace)
    pathFolder.Name  = "PathVisuals"

    local path = PathfindingService:CreatePath({
        AgentRadius  = 3,
        AgentHeight  = 5,
        AgentCanJump = true,
        WaypointSpacing = 4,
    })

    local success = pcall(function()
        path:ComputeAsync(root.Position, targetPosition)
    end)

    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        for _, wp in ipairs(waypoints) do
            local dot         = Instance.new("Part", pathFolder)
            dot.Shape         = Enum.PartType.Ball
            dot.Size          = Vector3.new(1.2, 1.2, 1.2)
            dot.Color         = Color3.new(1, 1, 1)
            dot.Material      = Enum.Material.Neon
            dot.Anchored      = true
            dot.CanCollide    = false
            dot.Position      = wp.Position + Vector3.new(0, 1, 0)
            Instance.new("PointLight", dot).Brightness = 3
        end

        task.spawn(function()
            for _, wp in ipairs(waypoints) do
                if not pathFolder or pathFolder.Parent == nil then break end
                if humanoid.MoveDirection.Magnitude > 0.1 then
                    pathFolder:Destroy()
                    self:Notify("Pathfinding cancelled: Manual movement.", 3, Library)
                    return
                end
                if wp.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end
                humanoid:MoveTo(wp.Position)

                local finished, conn = false, nil
                conn = humanoid.MoveToFinished:Connect(function()
                    finished = true
                    conn:Disconnect()
                end)
                local t0 = tick()
                repeat
                    task.wait()
                    if humanoid.MoveDirection.Magnitude > 0.1 then
                        if pathFolder then pathFolder:Destroy() end
                        if conn then conn:Disconnect() end
                        self:Notify("Pathfinding interrupted.", 3, Library)
                        return
                    end
                until finished or (tick() - t0 > 2.5)
                if conn then conn:Disconnect() end
                local kids = pathFolder:GetChildren()
                if kids[1] then kids[1]:Destroy() end
            end
            if pathFolder then pathFolder:Destroy() end
        end)
    else
        self:Notify("Unable to calculate path.", 3, Library)
    end
end

function Functions:GetClosestPlayer(settings, cachedPlayers)
    settings      = settings or {}
    cachedPlayers = cachedPlayers or Services.SPlayers:GetPlayers()

    local mousePos     = Services.SUserInputService:GetMouseLocation()
    local mpX, mpY     = mousePos.X, mousePos.Y
    local myChar       = LocalPlayer.Character
    local myRoot       = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end
    local myPos        = myRoot.Position
    local fovRad       = settings.FOVRadius or 125
    local maxDist      = settings.MaxDistance or 500
    local aimPart      = settings.AimPart or "Head"
    local closestP     = nil
    local shortest     = math.huge

    local sticky = settings.CurrentTarget
    if settings.StickyTarget and sticky and sticky.Character then
        local hum = sticky.Character:FindFirstChild("Humanoid")
        if hum and hum.Health > 0 and self:TeamCheck(sticky, settings) and not self:IsProtected(sticky, settings.ProtectedUsers) then
            local part = sticky.Character:FindFirstChild(aimPart)
            if part then
                local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    local dx = sp.X - mpX
                    local dy = sp.Y - mpY
                    local dist = math.sqrt(dx*dx + dy*dy)
                    if dist <= fovRad * (settings.StickyTolerance or 1.4) then
                        if not settings.RequireVisible or self:IsVisible(sticky) then
                            return sticky
                        end
                    end
                end
            end
        end
    end

    for _, p in ipairs(cachedPlayers) do
        if p == LocalPlayer then continue end
        local char = p.Character
        if not char then continue end
        if settings.TargetHostilesOnly and not char:GetAttribute(settings.HostileAttribute or "Hostile") then continue end
        local hum = char:FindFirstChild("Humanoid")
        if not (hum and hum.Health > 0 and not char:FindFirstChildOfClass("ForceField")) then continue end
        if not self:TeamCheck(p, settings) then continue end
        if self:IsProtected(p, settings.ProtectedUsers) then continue end

        local part = char:FindFirstChild(aimPart)
        if not part then continue end
        local pp = part.Position
        local wx, wy, wz = myPos.X - pp.X, myPos.Y - pp.Y, myPos.Z - pp.Z
        if math.sqrt(wx*wx + wy*wy + wz*wz) > maxDist then continue end
        local sp, onScreen = Camera:WorldToViewportPoint(pp)
        if not onScreen then continue end
        local sdx = sp.X - mpX
        local sdy = sp.Y - mpY
        local screenDist = math.sqrt(sdx*sdx + sdy*sdy)
        if screenDist < shortest and screenDist <= fovRad then
            if not settings.RequireVisible or self:IsVisible(p) then
                closestP = p
                shortest  = screenDist
            end
        end
    end
    return closestP
end

function Functions:CreateWaypointVisual(name, pos, espFolder)
    espFolder = espFolder or workspace
    if espFolder:FindFirstChild(name) then espFolder[name]:Destroy() end
    local fixedPos = typeof(pos) == "Vector3" and pos or Vector3.new(pos.X, pos.Y, pos.Z)

    local anchor         = Instance.new("Part")
    anchor.Name          = name
    anchor.Transparency  = 1
    anchor.Anchored      = true
    anchor.CanCollide    = false
    anchor.Position      = fixedPos
    anchor.Parent        = espFolder

    local bbg            = Instance.new("BillboardGui")
    bbg.Name             = "MainGui"
    bbg.Adornee          = anchor
    bbg.Size             = UDim2.new(0, 250, 0, 50)
    bbg.AlwaysOnTop      = true
    bbg.Parent           = anchor

    local label           = Instance.new("TextLabel")
    label.Text            = name
    label.Size            = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3      = Color3.fromRGB(255, 255, 255)
    label.TextStrokeTransparency = 0
    label.Font            = Enum.Font.GothamBold
    label.TextSize        = 14
    label.Parent          = bbg

    local dot             = Instance.new("Frame")
    dot.Name              = "Dot"
    dot.Size              = UDim2.new(0, 4, 0, 4)
    dot.Position          = UDim2.new(0.5, -2, 1, 0)
    dot.BackgroundColor3  = Color3.fromRGB(255, 255, 255)
    dot.BorderSizePixel   = 0
    dot.Parent            = bbg
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
end

function Functions:ItemEsp(config)
    config = config or {}
    local esp = {
        Active              = false,
        Highlights          = {},
        SearchTerms         = config.SearchTerms         or {},
        TrackedItems        = config.TrackedItems         or {},
        SearchPath          = config.SearchPath           or workspace,
        FillColor           = config.FillColor            or Color3.fromRGB(0, 255, 200),
        OutlineColor        = config.OutlineColor         or Color3.fromRGB(255, 255, 255),
        FillTransparency    = config.FillTransparency     or 0.5,
        OutlineTransparency = config.OutlineTransparency  or 0.0,
        MaxDistance         = config.MaxDistance          or 500,
        AlwaysOnTop         = config.AlwaysOnTop          ~= false,
        NotifyOnSpawn       = config.NotifyOnSpawn        or false,
        ShowNames           = config.ShowNames            or false,
        NameColor           = config.NameColor            or Color3.fromRGB(255, 255, 255),
        NameTextSize        = config.NameTextSize         or 14,
        ShowDistance        = config.ShowDistance         or false,
        Library             = config.Library              or nil,
        SpawnNotifyCooldowns = {},
        ScanConn            = nil,
        UpdateConn          = nil,
        DescendantConn      = nil,
        ScanThread          = nil,
        DistThread          = nil,
    }

    local allPlayers = Services.SPlayers:GetPlayers()
    Services.SPlayers.PlayerAdded:Connect(function(p) allPlayers[#allPlayers+1] = p end)
    Services.SPlayers.PlayerRemoving:Connect(function(p)
        for i = #allPlayers, 1, -1 do if allPlayers[i] == p then table.remove(allPlayers, i) break end end
    end)

    local function getPos(inst)
        if inst:IsA("BasePart") then return inst.Position
        elseif inst:IsA("Model") then
            local primary = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
            if primary then return primary.Position end
        end
        return nil
    end

    local function isValid(inst)
        if not inst or not inst.Parent then return false end
        for _, p in ipairs(allPlayers) do
            if p.Character and inst:IsDescendantOf(p.Character) then return false end
        end
        local lchar = LocalPlayer.Character
        if lchar and inst:IsDescendantOf(lchar) then return false end
        return true
    end

    local function matchesSearch(inst)
        if type(esp.SearchTerms) ~= "table" or #esp.SearchTerms == 0 then return false end
        if not inst or not inst.Name then return false end
        local nl = string.lower(tostring(inst.Name))
        for _, term in ipairs(esp.SearchTerms) do
            if type(term) == "string" and string.find(nl, string.lower(term), 1, true) then
                return true
            end
        end
        return false
    end

    local function matchesTracked(inst)
        return esp.TrackedItems[inst] == true
    end

    local function shouldHighlight(inst)
        return matchesSearch(inst) or matchesTracked(inst)
    end

    local function removeHL(inst)
        local hl = esp.Highlights[inst]
        if hl then pcall(function() hl:Destroy() end) esp.Highlights[inst] = nil end
        if inst and inst.Parent then
            local bb = inst:FindFirstChild("DeproxItemLabel")
            if bb then pcall(function() bb:Destroy() end) end
        end
    end

    local function addHL(inst, isNewSpawn)
        if esp.Highlights[inst] then return end
        if not isValid(inst) then return end

        local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local myPos  = myRoot and myRoot.Position
        if myPos then
            local itemPos = getPos(inst)
            if itemPos and (myPos - itemPos).Magnitude > esp.MaxDistance then return end
        end

        local hl              = Instance.new("Highlight")
        hl.Name               = "DeproxItemHL"
        hl.Adornee            = inst
        hl.FillColor          = esp.FillColor
        hl.OutlineColor       = esp.OutlineColor
        hl.FillTransparency   = esp.FillTransparency
        hl.OutlineTransparency = esp.OutlineTransparency
        hl.DepthMode          = esp.AlwaysOnTop and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
        hl.Parent             = inst
        esp.Highlights[inst]  = hl

        if esp.ShowNames or esp.ShowDistance then
            local adornPart = inst:IsA("BasePart") and inst
                or (inst:IsA("Model") and (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")))
            if adornPart then
                local bb           = Instance.new("BillboardGui")
                bb.Name            = "DeproxItemLabel"
                bb.Adornee         = adornPart
                bb.AlwaysOnTop     = esp.AlwaysOnTop
                bb.Size            = UDim2.new(0, 100, 0, 40)
                bb.StudsOffset     = Vector3.new(0, 2, 0)
                bb.ResetOnSpawn    = false
                bb.Parent          = inst

                if esp.ShowNames then
                    local lbl                      = Instance.new("TextLabel", bb)
                    lbl.Name                       = "NameLabel"
                    lbl.Size                       = UDim2.new(1, 0, 0.5, 0)
                    lbl.BackgroundTransparency      = 1
                    lbl.Text                       = inst.Name
                    lbl.TextColor3                 = esp.NameColor
                    lbl.TextStrokeTransparency     = 0.5
                    lbl.TextStrokeColor3           = Color3.fromRGB(0, 0, 0)
                    lbl.Font                       = Enum.Font.GothamBold
                    lbl.TextSize                   = esp.NameTextSize
                end

                if esp.ShowDistance then
                    local dl                       = Instance.new("TextLabel", bb)
                    dl.Name                        = "DistLabel"
                    dl.Size                        = UDim2.new(1, 0, 0.5, 0)
                    dl.Position                    = UDim2.new(0, 0, 0.5, 0)
                    dl.BackgroundTransparency      = 1
                    dl.Text                        = "0m"
                    dl.TextColor3                  = Color3.fromRGB(200, 200, 200)
                    dl.TextStrokeTransparency      = 0.5
                    dl.TextStrokeColor3            = Color3.fromRGB(0, 0, 0)
                    dl.Font                        = Enum.Font.Gotham
                    dl.TextSize                    = math.max(10, esp.NameTextSize - 2)
                end
            end
        end

        if isNewSpawn and esp.NotifyOnSpawn then
            local key = inst.Name
            local now = tick()
            if not esp.SpawnNotifyCooldowns[key] or (now - esp.SpawnNotifyCooldowns[key]) >= 5 then
                esp.SpawnNotifyCooldowns[key] = now
                Functions:Notify("Item spawned: " .. inst.Name, 4, esp.Library)
            end
        end
    end

    local function cleanup()
        for inst, _ in pairs(esp.Highlights) do removeHL(inst) end
        if esp.ScanConn   then esp.ScanConn:Disconnect();   esp.ScanConn   = nil end
        if esp.UpdateConn then esp.UpdateConn:Disconnect(); esp.UpdateConn = nil end
        if esp.DescendantConn then esp.DescendantConn:Disconnect(); esp.DescendantConn = nil end
    end

    local function scan()
        if not esp.Active then return end
        local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local myPos  = myRoot and myRoot.Position

        for inst, _ in pairs(esp.Highlights) do
            if not inst or not inst.Parent or not inst:IsDescendantOf(workspace) then
                removeHL(inst)
            elseif myPos then
                local p = getPos(inst)
                if p and (myPos - p).Magnitude > esp.MaxDistance then removeHL(inst) end
            end
        end

        if #esp.SearchTerms == 0 and next(esp.TrackedItems) == nil then return end
        local path = esp.SearchPath or workspace

        task.defer(function()
            if not esp.Active then return end
            local descs = path:GetDescendants()
            local CHUNK = 50
            for i = 1, #descs, CHUNK do
                if not esp.Active then return end
                local myR = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                myPos     = myR and myR.Position
                for j = i, math.min(i + CHUNK - 1, #descs) do
                    local inst = descs[j]
                    if inst and inst.Parent and shouldHighlight(inst) and isValid(inst) then
                        local ip = getPos(inst)
                        if myPos and ip then
                            if (myPos - ip).Magnitude <= esp.MaxDistance then addHL(inst, false) end
                        elseif not myPos then
                            addHL(inst, false)
                        end
                    end
                end
                task.wait()
            end
        end)
    end

    local function hookDescendants()
        if esp.DescendantConn then esp.DescendantConn:Disconnect() esp.DescendantConn = nil end
        local path = esp.SearchPath or workspace
        esp.DescendantConn = path.DescendantAdded:Connect(function(inst)
            if not esp.Active then return end
            task.wait()
            if not inst or not inst.Parent then return end
            if shouldHighlight(inst) and isValid(inst) then
                local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                local myPos  = myRoot and myRoot.Position
                local ip     = getPos(inst)
                if myPos and ip then
                    if (myPos - ip).Magnitude <= esp.MaxDistance then addHL(inst, true) end
                elseif not myPos then
                    addHL(inst, true)
                end
            end
        end)
    end

    function esp:Start()
        cleanup()
        self.Active = true

        self.ScanThread = task.spawn(function()
            while self.Active do
                pcall(scan)
                task.wait(2)
            end
        end)

        self.DistThread = task.spawn(function()
            while self.Active do
                if self.ShowDistance then
                    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    local myPos  = myRoot and myRoot.Position
                    if myPos then
                        for inst, _ in pairs(self.Highlights) do
                            if inst and inst.Parent then
                                local bb = inst:FindFirstChild("DeproxItemLabel")
                                if bb then
                                    local dl = bb:FindFirstChild("DistLabel")
                                    if dl then
                                        local ip = getPos(inst)
                                        if ip then dl.Text = math.floor((myPos - ip).Magnitude) .. "m" end
                                    end
                                end
                            end
                        end
                    end
                end
                task.wait(0.1)
            end
        end)

        hookDescendants()
    end

    function esp:Stop()
        self.Active = false
        cleanup()
    end

    function esp:RefreshColors()
        for inst, hl in pairs(self.Highlights) do
            if hl and hl.Parent then
                hl.FillColor          = self.FillColor
                hl.OutlineColor       = self.OutlineColor
                hl.FillTransparency   = self.FillTransparency
                hl.OutlineTransparency = self.OutlineTransparency
            end
            if inst and inst.Parent then
                local bb = inst:FindFirstChild("DeproxItemLabel")
                if bb then
                    local lbl = bb:FindFirstChildOfClass("TextLabel")
                    if lbl then
                        lbl.TextColor3 = self.NameColor
                        lbl.TextSize   = self.NameTextSize
                    end
                end
            end
        end
    end

    function esp:Rescan()
        cleanup()
        self:Start()
        task.spawn(scan)
    end

    function esp:GetPosition(inst)
        return getPos(inst)
    end

    return esp
end

return Functions
