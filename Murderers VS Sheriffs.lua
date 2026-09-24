--[[
    PuckAFK Hub · DUELS
    Aim + ESP v1.0.12 · Manual Only

    Auto-execute has been removed completely.
    Execute this file manually each time you enter a DUELS place/server.
    The first run also disables remnants left by older auto-execute builds.
]]

print("[PuckAFK DUELS] v1.0.12 manual build starting...")


local compiler = loadstring or load
if type(compiler) ~= "function" then
    return warn("[PuckAFK DUELS] loadstring/load unavailable")
end

--// Manual-only build: disable remnants from older auto-execute releases.
-- No queue_on_teleport call is made anywhere in this script. If an older queued
-- loader is still waiting for the next teleport, removing/tombstoning its saved
-- core prevents it from re-arming itself in the destination place.
local __manualEnv = (getgenv and getgenv()) or _G
__manualEnv.__PUCKAFK_DUELS_TELEPORT_QUEUE_KEY = nil
__manualEnv.__PUCKAFK_DUELS_TELEPORT_QUEUED = nil

local __oldAutoExecFiles = {
    "PuckAFK_DUELS_Aim_ESP_v1.0.3_CORE.lua",
    "PuckAFK_DUELS_Aim_ESP_v1.0.4_CORE.lua",
    "PuckAFK_DUELS_Aim_ESP_v1.0.5_CORE.lua",
    "PuckAFK_DUELS_Aim_ESP_v1.0.6_CORE.lua",
    "PuckAFK_DUELS_Aim_ESP_v1.0.7_CORE.lua",
    "PuckAFK_DUELS_Aim_ESP_v1.0.8_CORE.lua",
    "PuckAFK_DUELS_Aim_ESP_v1.0.9_CORE.lua",
    "PuckAFK_DUELS_Aim_ESP_v1.0.10_CORE.lua",
    "PuckAFK_DUELS_Aim_ESP_v1.0.11_CORE.lua",
    "PuckAFK_DUELS_Aim_ESP_universe.txt",
}
for _, __file in ipairs(__oldAutoExecFiles) do
    if type(delfile) == "function" then
        pcall(delfile, __file)
    elseif type(writefile) == "function" and string.find(__file, "_CORE.lua", 1, true) then
        pcall(writefile, __file, 'return "PuckAFK DUELS auto-execute disabled"')
    end
end

local okUI, uiSource = pcall(function()
    return game:HttpGet("https://raw.githubusercontent.com/PuckAFK/Puck-Loader/main/ui/PuckUI.lua")
end)
if not okUI or type(uiSource) ~= "string" or #uiSource < 100 then
    return warn("[PuckAFK DUELS] failed to download PuckUI")
end

local uiChunk, uiError = compiler(uiSource)
if not uiChunk then
    return warn("[PuckAFK DUELS] PuckUI compile failed: " .. tostring(uiError))
end

local okPuck, PuckUI = pcall(uiChunk)
if not okPuck or type(PuckUI) ~= "table" or type(PuckUI.CreateWindow) ~= "function" then
    return warn("[PuckAFK DUELS] invalid PuckUI")
end

local ENV = (getgenv and getgenv()) or _G
if ENV.__PUCKAFK_DUELS_AIM_ESP_CLEANUP then
    pcall(ENV.__PUCKAFK_DUELS_AIM_ESP_CLEANUP)
end

--// Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

local PLACE_INFO = {
    [124848751642883] = {Name = "DUELS 1v1", Kind = "1v1"},
    [135856908115931] = {Name = "DUELS Murderers VS Sheriffs", Kind = "team"},
}
local placeInfo = PLACE_INFO[game.PlaceId] or {Name = "DUELS / Unknown Place", Kind = "dynamic"}

--// Configuration
local Config = {
    AimMode = "Custom",
    Aim = {
        Enabled = true,
        HoldRMB = true,
        VisibleCheck = true,
        AimPoint = "Head", -- Head / Upper Torso / Closest Part

        AutoShoot = false,
        AutoShootButton = "RMB", -- real physical button used to arm auto shoot
        AutoShootRadius = 10,
        AutoShootDelay = 0.00,

        FOV = 220,
        SmoothSpeed = 46,
        MaxDistance = 700,
        ShowFOV = true,

        StickyTarget = true,
        StickyMultiplier = 1.30,
        Prediction = true,
        PredictionTime = 0.06,
        PredictionSmoothing = 0.72,
        MaxPredictionOffset = 14,
        AdaptiveSmoothing = true,
        MicroSnapRadius = 1.5,
        TargetPriority = "Hybrid", -- Crosshair / Distance / Low Health / Hybrid
        SwitchDelay = 0.05,
        SwitchThreshold = 0.12,
        LockGrace = 0.18,
    },
    ESP = {
        Enabled = true,
        Boxes = true,
        Names = true,
        Health = true,
        Distance = true,
        Tracers = false,
        Chams = true,
        TeamAware = true,
        MaxDistance = 1200,
    },
}

local DEFAULT_AIM = {}
for k, v in pairs(Config.Aim) do DEFAULT_AIM[k] = v end
local DEFAULT_ESP = {}
for k, v in pairs(Config.ESP) do DEFAULT_ESP[k] = v end

--// Runtime state
local destroyed = false
local lockedTarget = nil
local lockedTargetLastInfo = nil
local lockedTargetLastValidAt = 0
local lastTargetChangeAt = 0
local lastAutoShotAt = 0
local targetVelocityHistory = setmetatable({}, {__mode = "k"})
local espObjects = {}
local connections = {}
local renderName = "__PuckAFK_DUELS_AimESP_" .. tostring(math.random(100000, 999999))

local function addConnection(connection)
    table.insert(connections, connection)
    return connection
end

local function now()
    return os.clock()
end

local function currentCamera()
    Camera = workspace.CurrentCamera or Camera
    return Camera
end

local function getCharacter(player)
    if not player then return nil end
    local character = player.Character
    if character and character.Parent then
        return character
    end
    return nil
end

local function getHumanoid(player)
    local character = getCharacter(player)
    if not character then return nil end
    return character:FindFirstChildOfClass("Humanoid")
end

local function getRoot(player)
    local character = getCharacter(player)
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character.PrimaryPart
end

local function getHealth(player)
    local humanoid = getHumanoid(player)
    if not humanoid then return 0, 100 end
    return math.max(tonumber(humanoid.Health) or 0, 0), math.max(tonumber(humanoid.MaxHealth) or 100, 1)
end

local function isAlive(player)
    if not player or player.Parent ~= Players then return false end
    if player:GetAttribute("Died") == true then return false end
    local humanoid = getHumanoid(player)
    local root = getRoot(player)
    return humanoid ~= nil and root ~= nil and humanoid.Health > 0
end

local function getLocalGame()
    return LocalPlayer:GetAttribute("Game")
end

local function getObservedGame()
    local live = LocalPlayer:GetAttribute("Game")
    if live ~= nil then return live end
    return LocalPlayer:GetAttribute("Spectating")
end

local function combatRuntimeActive()
    if getLocalGame() == nil then return false end
    if LocalPlayer:GetAttribute("Died") == true then return false end
    return isAlive(LocalPlayer)
end

local function getTeam(player)
    local team = player and player:GetAttribute("Team")
    if typeof(team) == "string" and team ~= "" then
        return team
    end
    return nil
end

local function sameTeam(a, b)
    local teamA = getTeam(a)
    local teamB = getTeam(b)
    return teamA ~= nil and teamB ~= nil and teamA == teamB
end

local function isRelevantPlayer(player)
    if not player or player == LocalPlayer then return false end
    local observedGame = getObservedGame()
    if observedGame == nil then return false end
    if player:GetAttribute("Game") ~= observedGame then return false end
    return isAlive(player)
end

local function isEnemy(player)
    if not player or player == LocalPlayer then return false end
    local localGame = getLocalGame()
    if localGame == nil then return false end
    if player:GetAttribute("Game") ~= localGame then return false end
    if not isAlive(player) then return false end

    -- DUELS team modes replicate TeamRed / TeamBlue through the Team attribute.
    -- In 1v1 / non-team modes Team may be absent, so the other player is hostile.
    if Config.ESP.TeamAware and sameTeam(LocalPlayer, player) then
        return false
    end
    return true
end

local function iterateEnemies(callback)
    for _, player in ipairs(Players:GetPlayers()) do
        if isEnemy(player) then
            callback(player)
        end
    end
end

local function iterateRelevantPlayers(callback)
    for _, player in ipairs(Players:GetPlayers()) do
        if isRelevantPlayer(player) then
            -- In a live match ESP should not draw teammates when team-aware mode is on.
            if getLocalGame() == nil or not Config.ESP.TeamAware or not sameTeam(LocalPlayer, player) then
                callback(player)
            end
        end
    end
end

local function worldToScreen(position)
    local cam = currentCamera()
    if not cam then return nil, false, nil end
    local v, onScreen = cam:WorldToViewportPoint(position)
    return Vector2.new(v.X, v.Y), onScreen and v.Z > 0, v.Z
end

local function screenCenter()
    local cam = currentCamera()
    if not cam then return Vector2.new(0, 0) end
    return cam.ViewportSize / 2
end

local function getClosestBodyPart(player)
    local character = getCharacter(player)
    local cam = currentCamera()
    if not character or not cam then return nil end

    local preferred = {
        "Head", "UpperTorso", "Torso", "LowerTorso",
        "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
        "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg",
        "HumanoidRootPart",
    }

    local centre = screenCenter()
    local best, bestDistance = nil, math.huge
    for _, name in ipairs(preferred) do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            local v, visible = cam:WorldToViewportPoint(part.Position)
            if visible and v.Z > 0 then
                local d = (Vector2.new(v.X, v.Y) - centre).Magnitude
                if d < bestDistance then
                    bestDistance = d
                    best = part
                end
            end
        end
    end
    return best or character:FindFirstChild("Head") or getRoot(player)
end

local function getAimPart(player)
    local character = getCharacter(player)
    if not character then return nil end

    if Config.Aim.AimPoint == "Closest Part" then
        return getClosestBodyPart(player)
    elseif Config.Aim.AimPoint == "Upper Torso" then
        return character:FindFirstChild("UpperTorso")
            or character:FindFirstChild("Torso")
            or character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChild("Head")
    end

    return character:FindFirstChild("Head")
        or character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or getRoot(player)
end

local function getRawVelocity(player, part)
    local source = part or getRoot(player)
    if source and source:IsA("BasePart") then
        local velocity = source.AssemblyLinearVelocity
        if typeof(velocity) == "Vector3" then
            return velocity
        end
        return source.Velocity
    end
    return Vector3.new(0, 0, 0)
end

local function getSmoothedVelocity(player, part)
    local raw = getRawVelocity(player, part)
    local history = targetVelocityHistory[player]
    local smoothing = math.clamp(tonumber(Config.Aim.PredictionSmoothing) or 0, 0, 0.98)
    if not history then
        history = raw
    else
        history = history:Lerp(raw, 1 - smoothing)
    end
    targetVelocityHistory[player] = history
    return history
end

local function getPredictedPosition(player, part)
    if not part then return nil end
    local raw = part.Position
    if not Config.Aim.Prediction then return raw end

    local velocity = getSmoothedVelocity(player, part)
    local offset = velocity * math.max(tonumber(Config.Aim.PredictionTime) or 0, 0)
    local maxOffset = math.max(tonumber(Config.Aim.MaxPredictionOffset) or 0, 0)
    if maxOffset > 0 and offset.Magnitude > maxOffset then
        offset = offset.Unit * maxOffset
    end
    return raw + offset
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = false

local function hasLineOfSight(player, targetPosition)
    if not Config.Aim.VisibleCheck then return true end
    local cam = currentCamera()
    if not cam or not targetPosition then return false end

    local exclude = {}
    local localCharacter = getCharacter(LocalPlayer)
    local targetCharacter = getCharacter(player)
    if localCharacter then table.insert(exclude, localCharacter) end
    if targetCharacter then table.insert(exclude, targetCharacter) end
    rayParams.FilterDescendantsInstances = exclude

    local origin = cam.CFrame.Position
    local direction = targetPosition - origin
    if direction.Magnitude <= 0.01 then return true end

    local result = workspace:Raycast(origin, direction, rayParams)
    return result == nil
end

local function targetInfo(player, fovMultiplier)
    if not isEnemy(player) then return nil end
    local part = getAimPart(player)
    if not part then return nil end

    local cam = currentCamera()
    if not cam then return nil end

    local root = getRoot(player)
    local stablePosition = root and root.Position or part.Position
    local distance = (stablePosition - cam.CFrame.Position).Magnitude
    if distance > Config.Aim.MaxDistance then return nil end

    local rawAimPosition = part.Position
    if not hasLineOfSight(player, rawAimPosition) then return nil end

    local stableScreen, stableOnScreen = worldToScreen(stablePosition)
    if not stableOnScreen then return nil end

    local rawScreenDistance = (stableScreen - screenCenter()).Magnitude
    local maxFov = Config.Aim.FOV * (fovMultiplier or 1)
    if rawScreenDistance > maxFov then return nil end

    local predicted = getPredictedPosition(player, part)
    local predictedScreen, predictedOnScreen = worldToScreen(predicted)
    if not predictedOnScreen then
        predicted = rawAimPosition
        predictedScreen = stableScreen
    end

    local predictedScreenDistance = (predictedScreen - screenCenter()).Magnitude
    local health, maxHealth = getHealth(player)
    local healthRatio = math.clamp(health / math.max(maxHealth, 1), 0, 1)
    local distanceRatio = math.clamp(distance / math.max(Config.Aim.MaxDistance, 1), 0, 1)
    local priority = tostring(Config.Aim.TargetPriority or "Hybrid")
    local score

    if priority == "Distance" then
        score = (rawScreenDistance * 0.35) + (distanceRatio * maxFov * 0.65)
    elseif priority == "Low Health" then
        score = (rawScreenDistance * 0.60) + (healthRatio * maxFov * 0.40)
    elseif priority == "Hybrid" then
        score = (rawScreenDistance * 0.65)
            + (distanceRatio * maxFov * 0.20)
            + (healthRatio * maxFov * 0.15)
    else
        score = rawScreenDistance
    end

    return {
        Player = player,
        Part = part,
        Position = predicted,
        RawPosition = rawAimPosition,
        Distance = distance,
        ScreenDistance = predictedScreenDistance,
        RawScreenDistance = rawScreenDistance,
        Score = score,
        Health = health,
        MaxHealth = maxHealth,
    }
end

local function findBestTarget()
    local bestInfo = nil
    iterateEnemies(function(player)
        local info = targetInfo(player, 1)
        if info and (not bestInfo or info.Score < bestInfo.Score) then
            bestInfo = info
        end
    end)
    return bestInfo
end

local function selectTarget()
    local t = now()
    local currentInfo = nil

    if lockedTarget and Config.Aim.StickyTarget then
        currentInfo = targetInfo(lockedTarget, Config.Aim.StickyMultiplier)
        if currentInfo then
            lockedTargetLastInfo = currentInfo
            lockedTargetLastValidAt = t
        elseif lockedTargetLastInfo and (t - lockedTargetLastValidAt) <= Config.Aim.LockGrace then
            currentInfo = lockedTargetLastInfo
        else
            lockedTarget = nil
            lockedTargetLastInfo = nil
        end
    end

    local bestInfo = findBestTarget()
    if not bestInfo then
        return currentInfo
    end

    if not lockedTarget then
        lockedTarget = bestInfo.Player
        lockedTargetLastInfo = bestInfo
        lockedTargetLastValidAt = t
        lastTargetChangeAt = t
        return bestInfo
    end

    if bestInfo.Player == lockedTarget then
        lockedTargetLastInfo = bestInfo
        lockedTargetLastValidAt = t
        return bestInfo
    end

    if not currentInfo then
        if (t - lastTargetChangeAt) >= Config.Aim.SwitchDelay then
            lockedTarget = bestInfo.Player
            lockedTargetLastInfo = bestInfo
            lockedTargetLastValidAt = t
            lastTargetChangeAt = t
            return bestInfo
        end
        return lockedTargetLastInfo
    end

    local requiredImprovement = math.clamp(tonumber(Config.Aim.SwitchThreshold) or 0, 0, 0.95)
    local thresholdScore = currentInfo.Score * (1 - requiredImprovement)
    if bestInfo.Score < thresholdScore and (t - lastTargetChangeAt) >= Config.Aim.SwitchDelay then
        lockedTarget = bestInfo.Player
        lockedTargetLastInfo = bestInfo
        lockedTargetLastValidAt = t
        lastTargetChangeAt = t
        return bestInfo
    end

    return currentInfo
end

--// Mouse-native aim backend
local mouseAimSupported = type(mousemoverel) == "function"
local mouseAimMoveConst = Vector2.new(1, 0.77) * math.rad(0.5)
local userGameSettings = nil
pcall(function()
    userGameSettings = UserSettings():GetService("UserGameSettings")
end)

local function wrapAimAngle(value)
    value = value % math.pi
    value = value - (value >= (math.pi / 2) and math.pi or 0)
    value = value + (value < -(math.pi / 2) and math.pi or 0)
    return value
end

local function getAimMouseSensitivity()
    local sensitivity = 1
    if userGameSettings then
        local ok, value = pcall(function() return userGameSettings.MouseSensitivity end)
        if ok and type(value) == "number" and value > 0 then sensitivity = value end
    end
    return math.max(sensitivity, 0.001)
end

local function moveAimWithMouse(cam, targetPosition, dt, responseSpeed, snap)
    if not mouseAimSupported or not cam or not targetPosition then return false end
    local offset = targetPosition - cam.CFrame.Position
    if offset.Magnitude <= 0.001 then return true end

    local facing = cam.CFrame.LookVector
    local targetDirection = offset.Unit
    local diffYaw = wrapAimAngle(math.atan2(facing.X, facing.Z) - math.atan2(targetDirection.X, targetDirection.Z))
    local diffPitch = math.asin(math.clamp(facing.Y, -1, 1)) - math.asin(math.clamp(targetDirection.Y, -1, 1))
    local denominator = mouseAimMoveConst * getAimMouseSensitivity()
    local delta = Vector2.new(
        diffYaw / math.max(math.abs(denominator.X), 0.000001),
        diffPitch / math.max(math.abs(denominator.Y), 0.000001)
    )

    local response = 1 - math.exp(-(math.max(responseSpeed, 0.01) * 0.68) * math.max(dt, 0))
    if snap then response = 1 end
    delta = delta * math.clamp(response, 0, 1)
    delta = Vector2.new(math.clamp(delta.X, -450, 450), math.clamp(delta.Y, -450, 450))

    return pcall(mousemoverel, delta.X, delta.Y)
end

local function mouseButtonHeld(name)
    local input = name == "LMB" and Enum.UserInputType.MouseButton1 or Enum.UserInputType.MouseButton2
    local ok, held = pcall(function() return UserInputService:IsMouseButtonPressed(input) end)
    return ok and held == true
end

--// DUELS revolver first-person handling
-- The inspected places use Gun_Pistol / T_DragonGun_Pistol firearm assets.
-- We also accept common revolver/pistol/gun names so skins/wrappers still work.
local revolverFirstPersonActive = false
local savedCameraMode = nil
local savedMinZoom = nil
local savedMaxZoom = nil
local savedCameraType = nil
local savedCameraSubject = nil
local savedMouseBehavior = nil
local savedHeadTransparency = setmetatable({}, {__mode = "k"})

local function firearmNameMatch(name)
    name = string.lower(tostring(name or ""))
    if name == "" then return false end
    return string.find(name, "gun_pistol", 1, true) ~= nil
        or string.find(name, "dragongun", 1, true) ~= nil
        or string.find(name, "revolver", 1, true) ~= nil
        or string.find(name, "pistol", 1, true) ~= nil
        or string.find(name, "sheriff", 1, true) ~= nil
end

local function isRevolverTool(tool)
    if not tool or not tool:IsA("Tool") then return false end
    if firearmNameMatch(tool.Name) then return true end

    -- Skinned DUELS weapons can keep a generic Tool name while the model/mesh
    -- below it carries the actual Gun_Pistol identifier.
    local ok, descendants = pcall(function() return tool:GetDescendants() end)
    if not ok or type(descendants) ~= "table" then return false end
    for i = 1, math.min(#descendants, 120) do
        local object = descendants[i]
        if object and firearmNameMatch(object.Name) then
            return true
        end
    end
    return false
end

local function getEquippedRevolver()
    local character = getCharacter(LocalPlayer)
    if not character then return nil end
    for _, child in ipairs(character:GetChildren()) do
        if isRevolverTool(child) then
            return child
        end
    end
    return nil
end

local function restoreRevolverCamera()
    if not revolverFirstPersonActive then
        return
    end
    revolverFirstPersonActive = false

    pcall(function()
        if savedMaxZoom ~= nil then LocalPlayer.CameraMaxZoomDistance = savedMaxZoom end
        if savedMinZoom ~= nil then LocalPlayer.CameraMinZoomDistance = savedMinZoom end
        if savedCameraMode ~= nil then LocalPlayer.CameraMode = savedCameraMode end
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default

        local cam = currentCamera()
        if cam then
            if savedCameraSubject ~= nil then cam.CameraSubject = savedCameraSubject end
            if savedCameraType ~= nil then cam.CameraType = savedCameraType end
        end
    end)

    for part, oldValue in pairs(savedHeadTransparency) do
        if part and part.Parent then
            pcall(function() part.LocalTransparencyModifier = oldValue end)
        end
        savedHeadTransparency[part] = nil
    end

    savedCameraMode = nil
    savedMinZoom = nil
    savedMaxZoom = nil
    savedCameraType = nil
    savedCameraSubject = nil
    savedMouseBehavior = nil
end

local function hideLocalHeadForFirstPerson(character)
    if not character then return end
    for _, object in ipairs(character:GetDescendants()) do
        if object:IsA("BasePart") then
            local hide = object.Name == "Head"
            if not hide then
                local parent = object.Parent
                hide = parent and parent:IsA("Accessory")
            end
            if hide then
                if savedHeadTransparency[object] == nil then
                    savedHeadTransparency[object] = object.LocalTransparencyModifier
                end
                object.LocalTransparencyModifier = 1
            end
        end
    end
end

local function updateRevolverFirstPerson(shouldForce)
    -- v1.0.7: first person is NOT an RMB-only action. The caller must prove that
    -- a fresh, current-frame target exists inside the BASE FOV circle. This keeps
    -- sticky retention/grace and out-of-circle enemies from causing false zoom.
    shouldForce = shouldForce == true
        and Config.Aim.Enabled
        and combatRuntimeActive()
        and mouseButtonHeld("RMB")

    if not shouldForce then
        restoreRevolverCamera()
        return
    end

    local cam = currentCamera()
    local character = getCharacter(LocalPlayer)
    local head = character and character:FindFirstChild("Head")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if not revolverFirstPersonActive then
        revolverFirstPersonActive = true
        pcall(function() savedCameraMode = LocalPlayer.CameraMode end)
        pcall(function() savedMinZoom = LocalPlayer.CameraMinZoomDistance end)
        pcall(function() savedMaxZoom = LocalPlayer.CameraMaxZoomDistance end)
        pcall(function() savedMouseBehavior = UserInputService.MouseBehavior end)
        if cam then
            pcall(function() savedCameraType = cam.CameraType end)
            pcall(function() savedCameraSubject = cam.CameraSubject end)
        end
    end

    -- DUELS can run its own camera controller, so changing only CameraMode/zoom is
    -- not enough. Reassert the player settings AND the real CurrentCamera every
    -- frame while RMB is held. This physically places the camera at the player's
    -- eye/head position so the revolver is genuinely aiming from first person.
    pcall(function()
        LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
        LocalPlayer.CameraMinZoomDistance = 0.5
        LocalPlayer.CameraMaxZoomDistance = 0.5
        -- Never pin the cursor. First-person zoom and aim are independent of MouseBehavior.
        UserInputService.MouseBehavior = savedMouseBehavior or Enum.MouseBehavior.Default
    end)

    if cam then
        pcall(function()
            cam.CameraType = Enum.CameraType.Custom
            if humanoid then cam.CameraSubject = humanoid end

            if head then
                local look = cam.CFrame.LookVector
                if look.Magnitude < 0.5 then
                    look = head.CFrame.LookVector
                end
                local eye = head.Position + Vector3.new(0, 0.12, 0)
                cam.CFrame = CFrame.lookAt(eye, eye + look, Vector3.new(0, 1, 0))
                cam.Focus = CFrame.new(eye + look * 12)
            end
        end)
    end

    hideLocalHeadForFirstPerson(character)
end

-- Final-pass camera pin. The game may run additional camera code after the normal
-- DUELS render callback. This pass does not rotate the view; it only forces the
-- camera origin to the local eye position while first-person RMB is active.
local function finalizeRmbFirstPersonCamera()
    if not revolverFirstPersonActive then return end

    local cam = currentCamera()
    local character = getCharacter(LocalPlayer)
    local head = character and character:FindFirstChild("Head")
    if not cam or not head then return end

    pcall(function()
        LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
        LocalPlayer.CameraMinZoomDistance = 0.5
        LocalPlayer.CameraMaxZoomDistance = 0.5
        UserInputService.MouseBehavior = savedMouseBehavior or Enum.MouseBehavior.Default

        local rotation = cam.CFrame - cam.CFrame.Position
        local eye = head.Position + Vector3.new(0, 0.12, 0)
        cam.CFrame = CFrame.new(eye) * rotation
        cam.Focus = CFrame.new(eye + cam.CFrame.LookVector * 12)
    end)
end

local function aimActive()
    if not Config.Aim.Enabled or not combatRuntimeActive() then
        lockedTarget = nil
        lockedTargetLastInfo = nil
        return false
    end
    if Config.Aim.HoldRMB and not mouseButtonHeld("RMB") then
        lockedTarget = nil
        lockedTargetLastInfo = nil
        return false
    end
    return true
end

local function autoShootActive()
    return Config.Aim.AutoShoot
        and combatRuntimeActive()
        and mouseButtonHeld(Config.Aim.AutoShootButton)
end

local function tryAutoShoot(info)
    if not info or not autoShootActive() then return end
    if info.ScreenDistance > Config.Aim.AutoShootRadius then return end
    if Config.Aim.VisibleCheck and not hasLineOfSight(info.Player, info.RawPosition) then return end

    local t = now()
    local delay = math.max(tonumber(Config.Aim.AutoShootDelay) or 0, 0)
    -- Synthetic input can otherwise flood click events every render frame.
    local minimumInterval = math.max(delay, 0.025)
    if (t - lastAutoShotAt) < minimumInterval then return end

    if type(mouse1click) == "function" then
        local ok = pcall(mouse1click)
        if ok then lastAutoShotAt = t end
    elseif type(mouse1press) == "function" and type(mouse1release) == "function" then
        local ok = pcall(function()
            mouse1press()
            task.defer(mouse1release)
        end)
        if ok then lastAutoShotAt = t end
    end
end

local function applyAim(dt, freshFovInfo)
    local shouldAim = aimActive()
    local shouldShoot = autoShootActive()

    -- When RMB aim is being used, only a fresh base-FOV target may drive aim.
    -- Do not fall back to sticky grace here: that is exactly what caused zoom/aim
    -- to look "ready" while nobody was actually inside the circle.
    if shouldAim and mouseButtonHeld("RMB") and not freshFovInfo then
        shouldAim = false
    end

    if not shouldAim and not shouldShoot then return end

    local info = freshFovInfo
    if not info then
        info = selectTarget()
    end
    if not info then return end

    -- Extra strict guard for live aiming. findBestTarget() already uses multiplier=1,
    -- but keep this check so future targeting changes cannot accidentally bypass it.
    if shouldAim then
        local baseFov = math.max(tonumber(Config.Aim.FOV) or 0, 0)
        local rawScreenDistance = tonumber(info.RawScreenDistance) or math.huge
        if rawScreenDistance > baseFov then
            shouldAim = false
        end
    end

    -- Do not force MouseBehavior=LockCenter. The aim can move the view/cursor naturally.

    local cam = currentCamera()
    if not cam then return end

    if shouldAim then
        local speed = math.max(tonumber(Config.Aim.SmoothSpeed) or 0.01, 0.01)
        if Config.Aim.AdaptiveSmoothing then
            local normalized = math.clamp(info.ScreenDistance / math.max(Config.Aim.FOV, 1), 0, 1)
            speed = speed * (0.55 + math.sqrt(normalized) * 1.45)
        end

        local snapRadius = math.max(tonumber(Config.Aim.MicroSnapRadius) or 0, 0)
        local shouldSnap = snapRadius > 0 and info.ScreenDistance <= snapRadius
        local usedMouse = moveAimWithMouse(cam, info.Position, dt, speed, shouldSnap)
        if not usedMouse then
            local current = cam.CFrame
            local desired = CFrame.lookAt(current.Position, info.Position)
            local alpha = shouldSnap and 1 or (1 - math.exp(-speed * math.max(dt, 0)))
            cam.CFrame = current:Lerp(desired, math.clamp(alpha, 0, 1))
        end
    end

    if shouldShoot then
        -- Reproject after aim correction so Shoot Radius tracks the corrected frame.
        local screen, visible = worldToScreen(info.Position)
        if screen and visible then
            info.ScreenDistance = (screen - screenCenter()).Magnitude
        end
        tryAutoShoot(info)
    end
end

--// GUI / ESP overlay
-- PlayerGui-only on purpose. Newer Roblox capability/security contexts can allow
-- a loader thread to parent into gethui/CoreGui, then reject later callbacks that
-- try to access those descendants with "lacking capability Plugin".
local guiParent = PlayerGui

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PuckAFK_DUELS_AimESP"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999999
ScreenGui.Parent = guiParent
pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end
end)

local OverlayFolder = Instance.new("Folder")
OverlayFolder.Name = "ESP"
OverlayFolder.Parent = ScreenGui

local function makeStroke(parent, thickness)
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = thickness or 1
    stroke.Color = Color3.fromRGB(255, 78, 78)
    stroke.Transparency = 0
    stroke.Parent = parent
    return stroke
end

local function makeText(parent)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Font = Enum.Font.GothamMedium
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextStrokeTransparency = 0.35
    label.TextSize = 13
    label.ZIndex = 10
    label.Parent = parent
    return label
end

local function createESP(player)
    if espObjects[player] then return espObjects[player] end

    local holder = Instance.new("Frame")
    holder.Name = "PlayerESP"
    holder.BackgroundTransparency = 1
    holder.BorderSizePixel = 0
    holder.Visible = false
    holder.ZIndex = 5
    holder.Parent = OverlayFolder

    local box = Instance.new("Frame")
    box.Name = "Box"
    box.BackgroundTransparency = 1
    box.BorderSizePixel = 0
    box.Size = UDim2.fromScale(1, 1)
    box.ZIndex = 5
    box.Parent = holder
    local boxStroke = makeStroke(box, 1.5)

    local nameLabel = makeText(holder)
    nameLabel.Name = "Name"
    nameLabel.AnchorPoint = Vector2.new(0.5, 1)
    nameLabel.Position = UDim2.new(0.5, 0, 0, -3)
    nameLabel.Size = UDim2.new(1.8, 0, 0, 18)
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center

    local infoLabel = makeText(holder)
    infoLabel.Name = "Info"
    infoLabel.AnchorPoint = Vector2.new(0.5, 0)
    infoLabel.Position = UDim2.new(0.5, 0, 1, 3)
    infoLabel.Size = UDim2.new(2.0, 0, 0, 18)
    infoLabel.TextXAlignment = Enum.TextXAlignment.Center

    local hpBack = Instance.new("Frame")
    hpBack.Name = "HealthBack"
    hpBack.AnchorPoint = Vector2.new(1, 0)
    hpBack.Position = UDim2.new(0, -4, 0, 0)
    hpBack.Size = UDim2.new(0, 4, 1, 0)
    hpBack.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
    hpBack.BorderSizePixel = 0
    hpBack.ZIndex = 6
    hpBack.Parent = holder

    local hpFill = Instance.new("Frame")
    hpFill.Name = "Health"
    hpFill.AnchorPoint = Vector2.new(0, 1)
    hpFill.Position = UDim2.new(0, 0, 1, 0)
    hpFill.Size = UDim2.fromScale(1, 1)
    hpFill.BackgroundColor3 = Color3.fromRGB(85, 255, 110)
    hpFill.BorderSizePixel = 0
    hpFill.ZIndex = 7
    hpFill.Parent = hpBack

    local tracer = Instance.new("Frame")
    tracer.Name = "Tracer"
    tracer.AnchorPoint = Vector2.new(0, 0.5)
    tracer.BackgroundColor3 = Color3.fromRGB(255, 78, 78)
    tracer.BorderSizePixel = 0
    tracer.Size = UDim2.fromOffset(0, 1)
    tracer.Visible = false
    tracer.ZIndex = 3
    tracer.Parent = OverlayFolder

    local highlight = Instance.new("Highlight")
    highlight.Name = "PuckAFK_DUELS_ESP"
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = Color3.fromRGB(255, 60, 60)
    highlight.FillTransparency = 0.82
    highlight.OutlineColor = Color3.fromRGB(255, 115, 115)
    highlight.OutlineTransparency = 0
    highlight.Enabled = false
    highlight.Parent = workspace

    local object = {
        Holder = holder,
        Box = box,
        BoxStroke = boxStroke,
        Name = nameLabel,
        Info = infoLabel,
        HealthBack = hpBack,
        HealthFill = hpFill,
        Tracer = tracer,
        Highlight = highlight,
    }
    espObjects[player] = object
    return object
end

local function hideESPObject(object)
    if not object then return end
    object.Holder.Visible = false
    object.Tracer.Visible = false
    object.Highlight.Enabled = false
end

local function removeESP(player)
    local object = espObjects[player]
    if not object then return end
    pcall(function() object.Holder:Destroy() end)
    pcall(function() object.Tracer:Destroy() end)
    pcall(function() object.Highlight:Destroy() end)
    espObjects[player] = nil
end

local function getBounds(player)
    local character = getCharacter(player)
    local cam = currentCamera()
    if not character or not cam then return nil end

    local ok, cf, size = pcall(character.GetBoundingBox, character)
    if not ok or not cf or not size then return nil end

    local half = size * 0.5
    local corners = {
        Vector3.new(-half.X, -half.Y, -half.Z), Vector3.new(-half.X, -half.Y, half.Z),
        Vector3.new(-half.X, half.Y, -half.Z), Vector3.new(-half.X, half.Y, half.Z),
        Vector3.new(half.X, -half.Y, -half.Z), Vector3.new(half.X, -half.Y, half.Z),
        Vector3.new(half.X, half.Y, -half.Z), Vector3.new(half.X, half.Y, half.Z),
    }

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local visibleCount = 0
    for _, localCorner in ipairs(corners) do
        local point = cf:PointToWorldSpace(localCorner)
        local v = cam:WorldToViewportPoint(point)
        if v.Z > 0 then
            visibleCount = visibleCount + 1
            minX = math.min(minX, v.X)
            minY = math.min(minY, v.Y)
            maxX = math.max(maxX, v.X)
            maxY = math.max(maxY, v.Y)
        end
    end

    if visibleCount < 2 then return nil end
    return minX, minY, math.max(maxX - minX, 2), math.max(maxY - minY, 2), character
end

local function updateTracer(frame, from, to)
    local delta = to - from
    local distance = delta.Magnitude
    local angle = math.deg(math.atan2(delta.Y, delta.X))
    frame.Position = UDim2.fromOffset(from.X, from.Y)
    frame.Size = UDim2.fromOffset(distance, 1)
    frame.Rotation = angle
end

local function updateESP()
    if not Config.ESP.Enabled then
        for _, object in pairs(espObjects) do hideESPObject(object) end
        return
    end

    local cam = currentCamera()
    if not cam then return end
    local seen = {}

    iterateRelevantPlayers(function(player)
        seen[player] = true
        local root = getRoot(player)
        if not root then return end

        local distance = (root.Position - cam.CFrame.Position).Magnitude
        if distance > Config.ESP.MaxDistance then
            local existing = espObjects[player]
            if existing then hideESPObject(existing) end
            return
        end

        local object = createESP(player)
        local minX, minY, width, height, model = getBounds(player)
        local locked = player == lockedTarget
        local mainColor = locked and Color3.fromRGB(100, 255, 125) or Color3.fromRGB(255, 78, 78)

        object.BoxStroke.Color = mainColor
        object.Tracer.BackgroundColor3 = mainColor
        object.Highlight.FillColor = mainColor
        object.Highlight.OutlineColor = mainColor
        object.Highlight.Adornee = model
        object.Highlight.Enabled = Config.ESP.Chams and model ~= nil

        if minX then
            object.Holder.Visible = true
            object.Holder.Position = UDim2.fromOffset(minX, minY)
            object.Holder.Size = UDim2.fromOffset(width, height)
            object.Box.Visible = Config.ESP.Boxes

            object.Name.Visible = Config.ESP.Names
            local team = getTeam(player)
            object.Name.Text = team and (player.DisplayName .. "  [" .. team .. "]") or player.DisplayName

            local health, maxHealth = getHealth(player)
            local ratio = math.clamp(health / math.max(maxHealth, 1), 0, 1)
            object.HealthBack.Visible = Config.ESP.Health
            object.HealthFill.Size = UDim2.fromScale(1, ratio)

            local info = {}
            if Config.ESP.Health then table.insert(info, tostring(math.floor(health + 0.5)) .. " HP") end
            if Config.ESP.Distance then table.insert(info, tostring(math.floor(distance + 0.5)) .. " studs") end
            object.Info.Visible = #info > 0
            object.Info.Text = table.concat(info, "  •  ")

            if Config.ESP.Tracers then
                local from = Vector2.new(cam.ViewportSize.X * 0.5, cam.ViewportSize.Y - 2)
                local to = Vector2.new(minX + width * 0.5, minY + height)
                updateTracer(object.Tracer, from, to)
                object.Tracer.Visible = true
            else
                object.Tracer.Visible = false
            end
        else
            object.Holder.Visible = false
            object.Tracer.Visible = false
        end
    end)

    for player, _ in pairs(espObjects) do
        if not seen[player] or not isAlive(player) then
            removeESP(player)
        end
    end
end

--// FOV ring
local FOVRing = Instance.new("Frame")
FOVRing.Name = "FOV"
FOVRing.AnchorPoint = Vector2.new(0.5, 0.5)
FOVRing.BackgroundTransparency = 1
FOVRing.BorderSizePixel = 0
FOVRing.ZIndex = 2
FOVRing.Parent = ScreenGui
local FOVCorner = Instance.new("UICorner")
FOVCorner.CornerRadius = UDim.new(1, 0)
FOVCorner.Parent = FOVRing
local FOVStroke = Instance.new("UIStroke")
FOVStroke.Thickness = 1
FOVStroke.Transparency = 0.25
FOVStroke.Color = Color3.fromRGB(255, 255, 255)
FOVStroke.Parent = FOVRing

local function updateFOV()
    local centre = screenCenter()
    local diameter = Config.Aim.FOV * 2
    FOVRing.Position = UDim2.fromOffset(centre.X, centre.Y)
    FOVRing.Size = UDim2.fromOffset(diameter, diameter)
    FOVRing.Visible = Config.Aim.ShowFOV and Config.Aim.Enabled and combatRuntimeActive()
    FOVStroke.Color = lockedTarget and Color3.fromRGB(100, 255, 125) or Color3.fromRGB(255, 255, 255)
end

--// PuckUI
local Window = PuckUI:CreateWindow({
    Name = "PuckAFK Hub · DUELS",
    GuiName = "PuckAFK_DUELS",
    ConfigId = "DUELS",
    Width = 500,
    Height = 560,
})

-- Belt-and-braces: PuckUI currently prefers PlayerGui too, but force this script's
-- window there so a future/forked UI build cannot silently fall back to CoreGui.
if Window and Window.ScreenGui then
    pcall(function()
        Window.ScreenGui.Parent = PlayerGui
    end)
end

local CombatTab = Window:CreateTab("Combat")
local LegitTab = Window:CreateTab("Legit")
local RageTab = Window:CreateTab("Rage")
local VisualTab = Window:CreateTab("Visuals")
local SettingsTab = Window:CreateTab("Settings")
local UIControls = {}

local function optionValue(value)
    return type(value) == "table" and value[1] or value
end

local function resetLock()
    lockedTarget = nil
    lockedTargetLastInfo = nil
    lockedTargetLastValidAt = 0
end

CombatTab:CreateSection("DUELS Integration")
local RuntimeStatusLabel = CombatTab:CreateLabel("Starting...")
CombatTab:CreateLabel("Uses DUELS Game / Team / Died attributes from the inspected client state.")

CombatTab:CreateSection("Auto Aim")
UIControls.AimEnabled = CombatTab:CreateToggle({
    Name = "Enable Auto Aim",
    CurrentValue = Config.Aim.Enabled,
    Callback = function(value)
        Config.Aim.Enabled = value == true
        if not Config.Aim.Enabled then resetLock() end
    end,
})
UIControls.AimActivation = CombatTab:CreateDropdown({
    Name = "Aim Activation",
    Options = {"Hold RMB", "Always On"},
    CurrentOption = {Config.Aim.HoldRMB and "Hold RMB" or "Always On"},
    Callback = function(value)
        Config.Aim.HoldRMB = optionValue(value) ~= "Always On"
        resetLock()
    end,
})
UIControls.AimPoint = CombatTab:CreateDropdown({
    Name = "Aim Point",
    Options = {"Head", "Upper Torso", "Closest Part"},
    CurrentOption = {Config.Aim.AimPoint},
    Callback = function(value)
        Config.Aim.AimPoint = optionValue(value) or "Head"
        resetLock()
    end,
})
UIControls.VisibleCheck = CombatTab:CreateToggle({
    Name = "Wall / Visibility Check",
    CurrentValue = Config.Aim.VisibleCheck,
    Callback = function(value)
        Config.Aim.VisibleCheck = value == true
        resetLock()
    end,
})
UIControls.StickyTarget = CombatTab:CreateToggle({
    Name = "Sticky Target",
    CurrentValue = Config.Aim.StickyTarget,
    Callback = function(value)
        Config.Aim.StickyTarget = value == true
        resetLock()
    end,
})

CombatTab:CreateSection("Auto Shoot")
UIControls.AutoShoot = CombatTab:CreateToggle({
    Name = "Enable Auto Shoot",
    CurrentValue = Config.Aim.AutoShoot,
    Callback = function(value)
        Config.Aim.AutoShoot = value == true
        lastAutoShotAt = 0
    end,
})
UIControls.AutoShootButton = CombatTab:CreateDropdown({
    Name = "Auto Shoot Button",
    Options = {"RMB", "LMB"},
    CurrentOption = {Config.Aim.AutoShootButton},
    Callback = function(value)
        local v = tostring(optionValue(value) or "RMB"):upper()
        Config.Aim.AutoShootButton = v == "LMB" and "LMB" or "RMB"
    end,
})
UIControls.AutoShootRadius = CombatTab:CreateSlider({
    Name = "Shoot Radius",
    Range = {2, 30}, Increment = 1, CurrentValue = Config.Aim.AutoShootRadius, Suffix = " px",
    Callback = function(value) Config.Aim.AutoShootRadius = value end,
})
UIControls.AutoShootDelay = CombatTab:CreateSlider({
    Name = "Extra Shot Delay",
    Range = {0, 0.50}, Increment = 0.01, CurrentValue = Config.Aim.AutoShootDelay, Suffix = " s",
    Callback = function(value) Config.Aim.AutoShootDelay = value end,
})
CombatTab:CreateLabel("Auto Shoot is armed only while your selected real mouse button is held.")

CombatTab:CreateSection("FOV / Response")
UIControls.ShowFOV = CombatTab:CreateToggle({
    Name = "Show FOV Circle", CurrentValue = Config.Aim.ShowFOV,
    Callback = function(value) Config.Aim.ShowFOV = value == true end,
})
UIControls.FOV = CombatTab:CreateSlider({
    Name = "FOV Radius", Range = {40, 600}, Increment = 5, CurrentValue = Config.Aim.FOV, Suffix = " px",
    Callback = function(value) Config.Aim.FOV = value; resetLock() end,
})
UIControls.AimSpeed = CombatTab:CreateSlider({
    Name = "Aim Speed", Range = {4, 120}, Increment = 1, CurrentValue = Config.Aim.SmoothSpeed,
    Callback = function(value) Config.Aim.SmoothSpeed = value end,
})
UIControls.AimDistance = CombatTab:CreateSlider({
    Name = "Aim Max Distance", Range = {100, 1500}, Increment = 25, CurrentValue = Config.Aim.MaxDistance, Suffix = " studs",
    Callback = function(value) Config.Aim.MaxDistance = value; resetLock() end,
})

CombatTab:CreateSection("Advanced Targeting")
UIControls.TargetPriority = CombatTab:CreateDropdown({
    Name = "Target Priority",
    Options = {"Crosshair", "Distance", "Low Health", "Hybrid"},
    CurrentOption = {Config.Aim.TargetPriority},
    Callback = function(value) Config.Aim.TargetPriority = optionValue(value) or "Hybrid"; resetLock() end,
})
UIControls.Prediction = CombatTab:CreateToggle({
    Name = "Motion Prediction", CurrentValue = Config.Aim.Prediction,
    Callback = function(value) Config.Aim.Prediction = value == true end,
})
UIControls.PredictionTime = CombatTab:CreateSlider({
    Name = "Prediction Time", Range = {0, 0.30}, Increment = 0.01, CurrentValue = Config.Aim.PredictionTime, Suffix = " s",
    Callback = function(value) Config.Aim.PredictionTime = value end,
})
UIControls.AdaptiveSmoothing = CombatTab:CreateToggle({
    Name = "Adaptive Smoothing", CurrentValue = Config.Aim.AdaptiveSmoothing,
    Callback = function(value) Config.Aim.AdaptiveSmoothing = value == true end,
})
UIControls.MicroSnap = CombatTab:CreateSlider({
    Name = "Micro Snap Radius", Range = {0, 10}, Increment = 0.5, CurrentValue = Config.Aim.MicroSnapRadius, Suffix = " px",
    Callback = function(value) Config.Aim.MicroSnapRadius = value end,
})
UIControls.SwitchDelay = CombatTab:CreateSlider({
    Name = "Target Switch Delay", Range = {0, 0.30}, Increment = 0.01, CurrentValue = Config.Aim.SwitchDelay, Suffix = " s",
    Callback = function(value) Config.Aim.SwitchDelay = value end,
})
UIControls.LockGrace = CombatTab:CreateSlider({
    Name = "Target Lock Grace", Range = {0, 0.50}, Increment = 0.01, CurrentValue = Config.Aim.LockGrace, Suffix = " s",
    Callback = function(value) Config.Aim.LockGrace = value end,
})
UIControls.SwitchThreshold = CombatTab:CreateSlider({
    Name = "Switch Improvement Required", Range = {0, 0.50}, Increment = 0.01, CurrentValue = Config.Aim.SwitchThreshold,
    Callback = function(value) Config.Aim.SwitchThreshold = value end,
})
UIControls.PredictionSmoothing = CombatTab:CreateSlider({
    Name = "Prediction Stability", Range = {0, 0.95}, Increment = 0.01, CurrentValue = Config.Aim.PredictionSmoothing,
    Callback = function(value) Config.Aim.PredictionSmoothing = value end,
})
UIControls.MaxPredictionOffset = CombatTab:CreateSlider({
    Name = "Max Prediction Offset", Range = {0, 30}, Increment = 1, CurrentValue = Config.Aim.MaxPredictionOffset, Suffix = " studs",
    Callback = function(value) Config.Aim.MaxPredictionOffset = value end,
})

local function syncUI()
    local pairsToSet = {
        {UIControls.AimEnabled, Config.Aim.Enabled},
        {UIControls.AimActivation, Config.Aim.HoldRMB and "Hold RMB" or "Always On"},
        {UIControls.AimPoint, Config.Aim.AimPoint},
        {UIControls.VisibleCheck, Config.Aim.VisibleCheck},
        {UIControls.StickyTarget, Config.Aim.StickyTarget},
        {UIControls.AutoShoot, Config.Aim.AutoShoot},
        {UIControls.AutoShootButton, Config.Aim.AutoShootButton},
        {UIControls.AutoShootRadius, Config.Aim.AutoShootRadius},
        {UIControls.AutoShootDelay, Config.Aim.AutoShootDelay},
        {UIControls.ShowFOV, Config.Aim.ShowFOV},
        {UIControls.FOV, Config.Aim.FOV},
        {UIControls.AimSpeed, Config.Aim.SmoothSpeed},
        {UIControls.AimDistance, Config.Aim.MaxDistance},
        {UIControls.TargetPriority, Config.Aim.TargetPriority},
        {UIControls.Prediction, Config.Aim.Prediction},
        {UIControls.PredictionTime, Config.Aim.PredictionTime},
        {UIControls.AdaptiveSmoothing, Config.Aim.AdaptiveSmoothing},
        {UIControls.MicroSnap, Config.Aim.MicroSnapRadius},
        {UIControls.SwitchDelay, Config.Aim.SwitchDelay},
        {UIControls.LockGrace, Config.Aim.LockGrace},
        {UIControls.SwitchThreshold, Config.Aim.SwitchThreshold},
        {UIControls.PredictionSmoothing, Config.Aim.PredictionSmoothing},
        {UIControls.MaxPredictionOffset, Config.Aim.MaxPredictionOffset},
    }
    for _, pair in ipairs(pairsToSet) do
        if pair[1] and pair[1].Set then pcall(function() pair[1]:Set(pair[2]) end) end
    end
end

local function applyPreset(name, values, description)
    Config.AimMode = name
    for key, value in pairs(values) do
        if Config.Aim[key] ~= nil then Config.Aim[key] = value end
    end
    resetLock()
    syncUI()
    PuckUI:Notify({Title = name, Content = description or "Preset applied", Duration = 2.2})
end

LegitTab:CreateSection("Legit Aim")
LegitTab:CreateParagraph({
    Title = "Legit mode",
    Content = "Smooth visible-target aiming. These presets keep wall checks enabled and require RMB.",
    Height = 64,
})
LegitTab:CreateButton({Name = "Legit • Subtle", Callback = function()
    applyPreset("Legit • Subtle", {
        Enabled=true, HoldRMB=true, VisibleCheck=true, AimPoint="Head", Prediction=true,
        PredictionTime=0.04, PredictionSmoothing=0.82, MaxPredictionOffset=10,
        SwitchThreshold=0.22, LockGrace=0.24, AdaptiveSmoothing=true, MicroSnapRadius=0.5,
        TargetPriority="Hybrid", SwitchDelay=0.12, FOV=80, SmoothSpeed=13,
        MaxDistance=700, StickyTarget=true, StickyMultiplier=1.15, ShowFOV=false,
    }, "Hold RMB • 80px FOV • subtle smoothing")
end})
LegitTab:CreateButton({Name = "Legit • Balanced", Callback = function()
    applyPreset("Legit • Balanced", {
        Enabled=true, HoldRMB=true, VisibleCheck=true, AimPoint="Head", Prediction=true,
        PredictionTime=0.06, PredictionSmoothing=0.78, MaxPredictionOffset=12,
        SwitchThreshold=0.18, LockGrace=0.22, AdaptiveSmoothing=true, MicroSnapRadius=1,
        TargetPriority="Hybrid", SwitchDelay=0.08, FOV=120, SmoothSpeed=22,
        MaxDistance=700, StickyTarget=true, StickyMultiplier=1.20, ShowFOV=true,
    }, "Hold RMB • 120px FOV • balanced response")
end})
LegitTab:CreateButton({Name = "Legit • Strong", Callback = function()
    applyPreset("Legit • Strong", {
        Enabled=true, HoldRMB=true, VisibleCheck=true, AimPoint="Head", Prediction=true,
        PredictionTime=0.07, PredictionSmoothing=0.72, MaxPredictionOffset=14,
        SwitchThreshold=0.14, LockGrace=0.18, AdaptiveSmoothing=true, MicroSnapRadius=1.5,
        TargetPriority="Crosshair", SwitchDelay=0.05, FOV=180, SmoothSpeed=36,
        MaxDistance=700, StickyTarget=true, StickyMultiplier=1.25, ShowFOV=true,
    }, "Hold RMB • 180px FOV • strong response")
end})

RageTab:CreateSection("Rage Aim")
RageTab:CreateParagraph({
    Title = "Rage mode",
    Content = "Aggressive target acquisition with larger FOV and faster response. Max can ignore wall checks.",
    Height = 68,
})
RageTab:CreateButton({Name = "Rage • Visible", Callback = function()
    applyPreset("Rage • Visible", {
        Enabled=true, HoldRMB=false, VisibleCheck=true, AimPoint="Head", Prediction=true,
        PredictionTime=0.08, PredictionSmoothing=0.62, MaxPredictionOffset=16,
        SwitchThreshold=0.07, LockGrace=0.14, AdaptiveSmoothing=false, MicroSnapRadius=4,
        TargetPriority="Crosshair", SwitchDelay=0, FOV=500, SmoothSpeed=92,
        MaxDistance=1000, StickyTarget=true, StickyMultiplier=1.45, ShowFOV=true,
    }, "Always On • 500px FOV • visible targets only")
end})
RageTab:CreateButton({Name = "Rage • Max", Callback = function()
    applyPreset("Rage • Max", {
        Enabled=true, HoldRMB=false, VisibleCheck=false, AimPoint="Closest Part", Prediction=true,
        PredictionTime=0.10, PredictionSmoothing=0.55, MaxPredictionOffset=18,
        SwitchThreshold=0.03, LockGrace=0.12, AdaptiveSmoothing=false, MicroSnapRadius=8,
        TargetPriority="Crosshair", SwitchDelay=0, FOV=600, SmoothSpeed=120,
        MaxDistance=1500, StickyTarget=true, StickyMultiplier=1.60, ShowFOV=true,
    }, "Always On • maximum FOV / response • ignores walls")
end})

VisualTab:CreateSection("ESP")
UIControls.ESPEnabled = VisualTab:CreateToggle({Name="Enable ESP", CurrentValue=Config.ESP.Enabled, Callback=function(v) Config.ESP.Enabled=v==true end})
UIControls.Boxes = VisualTab:CreateToggle({Name="Boxes", CurrentValue=Config.ESP.Boxes, Callback=function(v) Config.ESP.Boxes=v==true end})
UIControls.Names = VisualTab:CreateToggle({Name="Names", CurrentValue=Config.ESP.Names, Callback=function(v) Config.ESP.Names=v==true end})
UIControls.Health = VisualTab:CreateToggle({Name="Health", CurrentValue=Config.ESP.Health, Callback=function(v) Config.ESP.Health=v==true end})
UIControls.Distance = VisualTab:CreateToggle({Name="Distance", CurrentValue=Config.ESP.Distance, Callback=function(v) Config.ESP.Distance=v==true end})
UIControls.Chams = VisualTab:CreateToggle({Name="Chams", CurrentValue=Config.ESP.Chams, Callback=function(v) Config.ESP.Chams=v==true end})
UIControls.Tracers = VisualTab:CreateToggle({Name="Tracers", CurrentValue=Config.ESP.Tracers, Callback=function(v) Config.ESP.Tracers=v==true end})
UIControls.TeamAware = VisualTab:CreateToggle({
    Name="Ignore Teammates", CurrentValue=Config.ESP.TeamAware,
    Callback=function(v) Config.ESP.TeamAware=v==true; resetLock() end,
})
VisualTab:CreateSection("ESP Range")
UIControls.ESPDistance = VisualTab:CreateSlider({
    Name="ESP Max Distance", Range={100,3000}, Increment=50, CurrentValue=Config.ESP.MaxDistance, Suffix=" studs",
    Callback=function(v) Config.ESP.MaxDistance=v end,
})
VisualTab:CreateLabel("ESP also follows the DUELS Spectating attribute after death / while spectating.")

SettingsTab:CreateSection("DUELS")
SettingsTab:CreateButton({Name="Reset Aim Settings", Callback=function()
    for k, v in pairs(DEFAULT_AIM) do Config.Aim[k] = v end
    Config.AimMode = "Custom"
    resetLock(); syncUI()
    PuckUI:Notify({Title="DUELS", Content="Aim settings reset", Duration=2})
end})
SettingsTab:CreateButton({Name="Reset ESP Settings", Callback=function()
    for k, v in pairs(DEFAULT_ESP) do Config.ESP[k] = v end
    if UIControls.ESPEnabled and UIControls.ESPEnabled.Set then UIControls.ESPEnabled:Set(Config.ESP.Enabled) end
    if UIControls.Boxes and UIControls.Boxes.Set then UIControls.Boxes:Set(Config.ESP.Boxes) end
    if UIControls.Names and UIControls.Names.Set then UIControls.Names:Set(Config.ESP.Names) end
    if UIControls.Health and UIControls.Health.Set then UIControls.Health:Set(Config.ESP.Health) end
    if UIControls.Distance and UIControls.Distance.Set then UIControls.Distance:Set(Config.ESP.Distance) end
    if UIControls.Chams and UIControls.Chams.Set then UIControls.Chams:Set(Config.ESP.Chams) end
    if UIControls.Tracers and UIControls.Tracers.Set then UIControls.Tracers:Set(Config.ESP.Tracers) end
    if UIControls.TeamAware and UIControls.TeamAware.Set then UIControls.TeamAware:Set(Config.ESP.TeamAware) end
    if UIControls.ESPDistance and UIControls.ESPDistance.Set then UIControls.ESPDistance:Set(Config.ESP.MaxDistance) end
    PuckUI:Notify({Title="DUELS", Content="ESP settings reset", Duration=2})
end})

local cleanup
SettingsTab:CreateButton({Name="Unload DUELS", Callback=function() if cleanup then cleanup() end end})

local function runtimeStatusText()
    local liveGame = LocalPlayer:GetAttribute("Game")
    local spectating = LocalPlayer:GetAttribute("Spectating")
    local team = getTeam(LocalPlayer)
    local state
    if liveGame ~= nil and LocalPlayer:GetAttribute("Died") ~= true then
        state = "COMBAT"
    elseif spectating ~= nil or LocalPlayer:GetAttribute("Died") == true then
        state = "SPECTATING / DEAD"
    else
        state = "LOBBY / IDLE"
    end
    local teamText = team and (" • " .. team) or ""
    return placeInfo.Name .. " • " .. state .. teamText
end

cleanup = function()
    if destroyed then return end
    destroyed = true
    restoreRevolverCamera()
    resetLock()
    pcall(function() RunService:UnbindFromRenderStep(renderName) end)
    pcall(function() RunService:UnbindFromRenderStep(renderName .. "_FirstPersonFinal") end)
    for _, connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    for player, _ in pairs(espObjects) do removeESP(player) end
    pcall(function() ScreenGui:Destroy() end)
    pcall(function() Window:Destroy() end)
    if ENV.__PUCKAFK_DUELS_AIM_ESP_CLEANUP == cleanup then
        ENV.__PUCKAFK_DUELS_AIM_ESP_CLEANUP = nil
    end
end
ENV.__PUCKAFK_DUELS_AIM_ESP_CLEANUP = cleanup

if Window.SetCloseCallback then
    Window:SetCloseCallback(function() cleanup() end)
end

addConnection(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = workspace.CurrentCamera
end))
addConnection(Players.PlayerRemoving:Connect(function(player)
    if player == lockedTarget then resetLock() end
    removeESP(player)
    targetVelocityHistory[player] = nil
end))
addConnection(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
    restoreRevolverCamera()
    pcall(function()
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end)
end))
local function refreshRuntimeStatus()
    if destroyed or not RuntimeStatusLabel or not RuntimeStatusLabel.Set then
        return
    end
    pcall(function()
        RuntimeStatusLabel:Set(runtimeStatusText())
    end)
end

local function onMatchStateChanged()
    resetLock()
    refreshRuntimeStatus()
end

-- Status only depends on replicated DUELS attributes, so update exactly when those
-- attributes change. This avoids a background worker repeatedly touching GUI state.
addConnection(LocalPlayer:GetAttributeChangedSignal("Game"):Connect(onMatchStateChanged))
addConnection(LocalPlayer:GetAttributeChangedSignal("Spectating"):Connect(refreshRuntimeStatus))
addConnection(LocalPlayer:GetAttributeChangedSignal("Team"):Connect(onMatchStateChanged))
addConnection(LocalPlayer:GetAttributeChangedSignal("Died"):Connect(onMatchStateChanged))
refreshRuntimeStatus()

-- Run very late in the render pipeline so DUELS' own camera controller cannot
-- immediately overwrite the forced revolver first-person camera in the same frame.
RunService:BindToRenderStep(renderName, Enum.RenderPriority.Last.Value - 5, function(dt)
    if destroyed then return end

    if not mouseButtonHeld("RMB") then
        pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
    end

    -- Fresh base-FOV gate: findBestTarget() calls targetInfo(..., 1), so only an
    -- enemy currently inside the actual visible FOV circle can activate first person.
    -- This deliberately bypasses StickyMultiplier and LockGrace for the zoom decision.
    local freshFovInfo = nil
    if Config.Aim.Enabled and combatRuntimeActive() and mouseButtonHeld("RMB") then
        freshFovInfo = findBestTarget()
    end

    updateRevolverFirstPerson(freshFovInfo ~= nil)
    applyAim(dt, freshFovInfo)
    updateFOV()
    updateESP()
end)

-- Run after the main callback and after ordinary camera priorities. This catches
-- custom DUELS camera code that otherwise moves the camera back out in the same frame.
RunService:BindToRenderStep(renderName .. "_FirstPersonFinal", Enum.RenderPriority.Last.Value + 100, function()
    if destroyed then return end
    finalizeRmbFirstPersonCamera()
end)

PuckUI:Notify({
    Title = "PuckAFK · DUELS",
    Content = "Loaded " .. placeInfo.Name .. " • v1.0.12 manual only",
    Duration = 3,
})

print("[PuckAFK DUELS] v1.0.12 loaded successfully — auto-execute disabled")
