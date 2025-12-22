repeat wait() until game:IsLoaded()
local RS = game.ReplicatedStorage
local NetworkController = require(RS.Client.Controllers.All.NetworkController)
local BlinkClient = require(RS.Blink.Client)
local NetworkService = require(RS.Services.NetworkService)
local Promise = require(RS.Modules.Promise)
local Entity = require(RS.Modules.Entity)
local lplr = game.Players.LocalPlayer
local ToolService = require(RS.Services.ToolService)
local Melee = require(RS.Constants.Melee)
local ViewmodelController = require(game:GetService("ReplicatedStorage").Client.Controllers.All.ViewmodelController)

local FOV_SIZE = 280
local ATTACK_DISTANCE = 20
local _attackCooldown = false
local _attacking = false
local _viewmodelAnimationCooldown = false
local _thirdPersonAnimCooldown = false
local _foundPerfection = false
local _foundEntity = false

local mouse = lplr:GetMouse()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Ping = 50
local PingDifference = 20
local CPS = 6


-- // Protection // --

hookfunction(NetworkService.SendReport, function(...) end)

function update_cps(cps)
    BlinkClient.player_state.update_cps.fire(cps)
end

--[[ // block the old updater and replace with the spoofed oned

old = hookfunction(NetworkService.GetPing, function(self, ...)
    local source = debug.getinfo(2).source
    if source and string.find(source, "NetworkController") then
        return {
            andThen = function(self, callback)
                return self
            end
        }
    end
    return old(self, ...)
end)

spawn(function()
    while task.wait(1) do
        NetworkController.Ping = (Ping + math.random(-PingDifference, PingDifference)) / 1000
    end
end)
]]
-- // Utility Functions

function GetNearestPlayer(maxDist)
    local nearest = nil
    local shortestDistance = maxDist or math.huge

    for i, v in pairs(game.Players:GetPlayers()) do
        if v ~= lplr and v.Character and v.Character:FindFirstChild("HumanoidRootPart") then
            local distance = (v.Character.HumanoidRootPart.Position - lplr.Character.HumanoidRootPart.Position).Magnitude
            if distance < shortestDistance then
                nearest = v
                shortestDistance = distance
            end
        end
    end

    return nearest
end

function getSword(instance)
    local sword = "WoodenSword"
    if lplr.Character:FindFirstChild("WoodenSword") then
        sword = not instance and "WoodenSword" or lplr.Character:FindFirstChild("WoodenSword")
    elseif lplr.Character:FindFirstChild("Sword") then
        sword = not instance and "Sword" or lplr.Character:FindFirstChild("Sword")
    elseif lplr.Character:FindFirstChild("GoldSword") then
        sword = not instance and "GoldSword" or lplr.Character:FindFirstChild("GoldSword")
    elseif lplr.Character:FindFirstChild("DiamondSword") then
        sword = not instance and "DiamondSword" or lplr.Character:FindFirstChild("DiamondSword")
    end
    return sword
end


-- // Legit Killaura

local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 2
fovCircle.NumSides = 128
fovCircle.Radius = FOV_SIZE
fovCircle.Filled = false
fovCircle.Color = Color3.fromRGB(255, 255, 255)
fovCircle.Transparency = 1
fovCircle.Visible = true

local function IsPlayerInFOV(player)
    if not lplr.Character or not lplr.Character:FindFirstChild("HumanoidRootPart") then
        return false
    end
    
    if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
        return false
    end
    
    local camera = workspace.CurrentCamera
    local playerPos = player.Character.HumanoidRootPart.Position
    local screenPoint, onScreen = camera:WorldToViewportPoint(playerPos)
    
    if not onScreen then
        return false
    end
    
    local mousePos = Vector2.new(mouse.X, mouse.Y)
    local targetPos = Vector2.new(screenPoint.X, screenPoint.Y)
    local distance = (targetPos - mousePos).Magnitude
    
    return distance <= fovCircle.Radius
end

local function StrictWallCheckCamera(target)
    local camera = Workspace.CurrentCamera
    local character = lplr.Character
    if not character then return false end

    local targetPart = target:IsA("Model")
        and (target.PrimaryPart or target:FindFirstChild("HumanoidRootPart"))
        or target

    if not targetPart then return false end

    local origin = camera.CFrame.Position
    local direction = targetPart.Position - origin

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {character}
    params.IgnoreWater = true

    local result = Workspace:Raycast(origin, direction, params)

    return result and result.Instance:IsDescendantOf(target)
end

local TARGET_HZ = 60
local INTERVAL = 1 / TARGET_HZ
local accumulator = 0


RunService.RenderStepped:Connect(function(dt)
    accumulator += dt

    if accumulator < INTERVAL then
        return
    end

    accumulator -= INTERVAL
    fovCircle.Position = Vector2.new(mouse.X, mouse.Y)
    local nearest = GetNearestPlayer(ATTACK_DISTANCE)

    if nearest and IsPlayerInFOV(nearest) and StrictWallCheckCamera(nearest.Character) and not Entity.LocalEntity.State.IsBlocking then
        _foundEntity = true
        if not _attackCooldown and Melee.isInRange(lplr.Character.PrimaryPart.Position, nearest.Character.HumanoidRootPart.Position, Entity.LocalEntity.State.Reach) then
            _foundPerfection = true
            _attackCooldown = true
            fovCircle.Color = Color3.fromRGB(170, 0, 255)
            update_cps(6 + math.random(-2, 2))
            if _viewmodelAnimationCooldown == false then
                task.defer(function()
                    _viewmodelAnimationCooldown = true
                    ViewmodelController:PlayAnimation(getSword())
                    _viewmodelAnimationCooldown = false
                end)
            end

            if _thirdPersonAnimCooldown == false then
                _thirdPersonAnimCooldown = true
                if lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart") then
                    local success, swrd = pcall(function()
                        return getSword(true).Animations.Swing
                    end)
                    pcall(function() if swrd then lplr.Character.Humanoid:WaitForChild("Animator"):LoadAnimation(swrd):Play() end end)
                end
                _thirdPersonAnimCooldown = false
            end

            local id = Entity.FindByCharacter(nearest.Character).Id
            local v36 = {
                ["target_entity_id"] = id,
                ["is_crit"] = lplr.Character.PrimaryPart.AssemblyLinearVelocity.Y < 0,
                ["weapon_name"] = getSword(),
                ["extra"] = {
                    ["rizz"] = "Bro.",
                    ["owo"] = "What's this? OwO",
                    ["those"] = workspace.Name == "Ok"
                }
            }
            BlinkClient.item_action.attack_entity.fire(v36)
            ToolService:AttackPlayerWithSword(nearest.Character, lplr.Character.PrimaryPart.AssemblyLinearVelocity.Y < 0, getSword(), "\226\128\139")
            wait(Melee.COOLDOWN)
            _attackCooldown = false
        else
            _foundPerfection = false
        end
    else
        _foundEntity = false
        fovCircle.Color = Color3.fromRGB(255, 255, 255)
    end
end)
