local RunService = game:GetService("RunService")

local function isColliding(a, b)
    local aMin = a.Position - a.Size / 2
    local aMax = a.Position + a.Size / 2
    local bMin = b.Position - b.Size / 2
    local bMax = b.Position + b.Size / 2

    return (
        aMin.X <= bMax.X and aMax.X >= bMin.X and
        aMin.Y <= bMax.Y and aMax.Y >= bMin.Y and
        aMin.Z <= bMax.Z and aMax.Z >= bMin.Z
    )
end

local function resolveCollision(obj, other, data)
    local delta = obj.Position - other.Position
    local overlap = (obj.Size + other.Size) / 2 - Vector3.new(
        math.abs(delta.X),
        math.abs(delta.Y),
        math.abs(delta.Z)
    )

    if overlap.X < overlap.Y and overlap.X < overlap.Z then
        local direction = math.sign(delta.X)
        obj.Position = obj.Position + Vector3.new(overlap.X * direction, 0, 0)
        if math.sign(data.Velocity.X) ~= direction then
            data.Velocity = Vector3.new(0, data.Velocity.Y, data.Velocity.Z)
        end
    elseif overlap.Y < overlap.Z then
        local direction = math.sign(delta.Y)
        obj.Position = obj.Position + Vector3.new(0, overlap.Y * direction, 0)
        if math.sign(data.Velocity.Y) ~= direction then
            data.Velocity = Vector3.new(data.Velocity.X, 0, data.Velocity.Z)
        end
    else
        local direction = math.sign(delta.Z)
        obj.Position = obj.Position + Vector3.new(0, 0, overlap.Z * direction)
        if math.sign(data.Velocity.Z) ~= direction then
            data.Velocity = Vector3.new(data.Velocity.X, data.Velocity.Y, 0)
        end
    end
end

local Engine  = {}
local objects = {}
local bones   = {}
local rootBones  = {}
local animations = {}

function Engine:AddObject(obj)
    obj.Anchored   = true
    obj.CanCollide = false
    objects[obj] = {
        Velocity  = Vector3.new(0, 0, 0),
        Gravity   = Vector3.new(0, 0, 0),
        Collision = false,
        Floor     = nil,
        OnFloor   = false,
    }
end

function Engine:SetVelocity(obj, vel)
    if objects[obj] then objects[obj].Velocity = vel end
end

function Engine:SetGravity(obj, grav)
    if objects[obj] then objects[obj].Gravity = grav end
end

function Engine:SetCollision(obj, val)
    if objects[obj] then objects[obj].Collision = val end
end

function Engine:SetFloor(obj, val)
    if objects[obj] then
        objects[obj].Floor = val
        if val ~= nil then
            local halfH = obj.Size.Y / 2
            if obj.Position.Y - halfH < val then
                obj.Position = Vector3.new(obj.Position.X, val + halfH, obj.Position.Z)
                objects[obj].Velocity = Vector3.new(0, 0, 0)
            end
        end
    end
end

function Engine:IsOnFloor(obj)
    return objects[obj] and objects[obj].OnFloor
end

function Engine:AddBone(obj, parent)
    obj.Anchored   = true
    obj.CanCollide = false

    local parentCF = parent and bones[parent].worldCF or obj.CFrame
    local offset   = parentCF:Inverse() * obj.CFrame

    bones[obj] = {
        obj           = obj,
        parent        = parent or nil,
        children      = {},
        offset        = offset,
        localCF       = offset,
        worldCF       = obj.CFrame,
        pinned        = false,
        target        = nil,
        targetOffset  = CFrame.new(),
    }

    if parent and bones[parent] then
        table.insert(bones[parent].children, obj)
    else
        table.insert(rootBones, obj)
    end

    return obj
end

function Engine:SetBoneLocal(obj, cf)
    if bones[obj] then bones[obj].localCF = cf end
end

function Engine:SetBoneTarget(obj, target, offset)
    if bones[obj] then
        bones[obj].target       = target
        bones[obj].targetOffset = offset or CFrame.new()
    end
end

function Engine:SetBonePinned(obj, val)
    if bones[obj] then
        bones[obj].pinned = val
        if val and not objects[obj] then
            Engine:AddObject(obj)
        end
    end
end

local function updateBone(boneObj)
    local data = bones[boneObj]
    if not data then return end

    if data.target then
        local targetCF
        if typeof(data.target) == "Instance" then
            targetCF = data.target.CFrame
        elseif bones[data.target] then
            targetCF = bones[data.target].worldCF
        end
        if targetCF then
            data.worldCF = targetCF * data.targetOffset
        end
    elseif data.parent and bones[data.parent] then
        data.worldCF = bones[data.parent].worldCF * data.localCF
    else
        data.worldCF = data.localCF
    end

    if data.pinned and objects[boneObj] then
        data.worldCF = CFrame.new(boneObj.Position) *
            CFrame.fromMatrix(Vector3.zero, data.worldCF.XVector, data.worldCF.YVector)
    end

    boneObj.CFrame = data.worldCF

    for _, child in ipairs(data.children) do
        updateBone(child)
    end
end

function Engine:CreateAnimation(id, keyframes, easing)
    animations[id] = {
        keyframes = keyframes,
        easing    = easing or "Linear",
        playing   = false,
        loop      = false,
        time      = 0,
        speed     = 1,
        length    = keyframes[#keyframes].time,
    }
end

function Engine:PlayAnimation(id, loop, speed)
    local anim = animations[id]
    if anim then
        anim.playing = true
        anim.loop    = loop  or false
        anim.speed   = speed or 1
        anim.time    = 0
    end
end

function Engine:StopAnimation(id)
    if animations[id] then
        animations[id].playing = false
        animations[id].time    = 0
    end
end

local function applyEasing(t, style)
    if style == "EaseIn"     then return t * t
    elseif style == "EaseOut"    then return 1 - (1 - t)^2
    elseif style == "EaseInOut"  then
        return t < 0.5 and 2*t*t or 1 - (-2*t+2)^2/2
    end
    return t
end

local function tickAnimations(dt)
    for _, anim in pairs(animations) do
        if not anim.playing then continue end

        anim.time = anim.time + dt * anim.speed

        if anim.time >= anim.length then
            if anim.loop then
                anim.time = anim.time % anim.length
            else
                anim.time    = anim.length
                anim.playing = false
            end
        end

        local kf = anim.keyframes
        local kfA, kfB

        for i = 1, #kf - 1 do
            if anim.time >= kf[i].time and anim.time <= kf[i+1].time then
                kfA = kf[i]
                kfB = kf[i+1]
                break
            end
        end

        if not kfA then
            for boneObj, cf in pairs(kf[#kf].bones) do
                if bones[boneObj] then
                    bones[boneObj].localCF = cf
                end
            end
            continue
        end

        local segLen = kfB.time - kfA.time
        local t      = segLen > 0 and (anim.time - kfA.time) / segLen or 1
        t = applyEasing(t, anim.easing)

        for boneObj, cfA in pairs(kfA.bones) do
            local cfB = kfB.bones[boneObj]
            if cfB and bones[boneObj] then
                bones[boneObj].localCF = cfA:Lerp(cfB, t)
            end
        end
    end
end

RunService.Heartbeat:Connect(function(dt)
    for obj, data in pairs(objects) do
        local grav = data.Gravity
        if data.OnFloor then
            grav = Vector3.new(grav.X, 0, grav.Z)
        end
        data.Velocity = data.Velocity + grav * dt
        obj.Position  = obj.Position  + data.Velocity * dt
    end

    for obj, data in pairs(objects) do
        if data.Collision then
            for other in pairs(objects) do
                if obj ~= other and objects[other].Collision then
                    if tostring(obj) < tostring(other) then
                        if isColliding(obj, other) then
                            resolveCollision(obj, other, data)
                        end
                    end
                end
            end
        end
    end

    for obj, data in pairs(objects) do
        if data.Collision and data.Floor ~= nil then
            local floorY = data.Floor
            local halfH  = obj.Size.Y / 2
            if obj.Position.Y - halfH <= floorY then
                obj.Position = Vector3.new(obj.Position.X, floorY + halfH, obj.Position.Z)
                if data.Velocity.Y < 0 then
                    data.Velocity = Vector3.new(data.Velocity.X, 0, data.Velocity.Z)
                end
                data.OnFloor = math.abs(data.Velocity.Y) < 0.5
            else
                data.OnFloor = false
            end
        end
    end

    tickAnimations(dt)
    for _, root in ipairs(rootBones) do
        updateBone(root)
    end
end)

return Engine
