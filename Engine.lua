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

local function resolveCollision(obj, other, dataA, dataB)
    local delta = obj.Position - other.Position
    local overlap = (obj.Size + other.Size) / 2 - Vector3.new(
        math.abs(delta.X), math.abs(delta.Y), math.abs(delta.Z)
    )

    local mA = dataA.Mass
    local mB = dataB.Mass
    local totalMass = mA + mB
    local ratioA = mB / totalMass
    local ratioB = mA / totalMass
    local axis, axisDir

    if overlap.X < overlap.Y and overlap.X < overlap.Z then
        axis = "X"; axisDir = math.sign(delta.X)
        obj.Position   = obj.Position   + Vector3.new(overlap.X * axisDir * ratioA, 0, 0)
        other.Position = other.Position - Vector3.new(overlap.X * axisDir * ratioB, 0, 0)
    elseif overlap.Y < overlap.Z then
        axis = "Y"; axisDir = math.sign(delta.Y)
        obj.Position   = obj.Position   + Vector3.new(0, overlap.Y * axisDir * ratioA, 0)
        other.Position = other.Position - Vector3.new(0, overlap.Y * axisDir * ratioB, 0)
    else
        axis = "Z"; axisDir = math.sign(delta.Z)
        obj.Position   = obj.Position   + Vector3.new(0, 0, overlap.Z * axisDir * ratioA)
        other.Position = other.Position - Vector3.new(0, 0, overlap.Z * axisDir * ratioB)
    end

    local function exchangeAxis(vA, vB)
        return
            ((mA - mB) * vA + 2 * mB * vB) / totalMass,
            ((mB - mA) * vB + 2 * mA * vA) / totalMass
    end

    if axis == "X" then
        local nA, nB = exchangeAxis(dataA.Velocity.X, dataB.Velocity.X)
        dataA.Velocity = Vector3.new(nA, dataA.Velocity.Y, dataA.Velocity.Z)
        dataB.Velocity = Vector3.new(nB, dataB.Velocity.Y, dataB.Velocity.Z)
    elseif axis == "Y" then
        local nA, nB = exchangeAxis(dataA.Velocity.Y, dataB.Velocity.Y)
        dataA.Velocity = Vector3.new(dataA.Velocity.X, nA, dataA.Velocity.Z)
        dataB.Velocity = Vector3.new(dataB.Velocity.X, nB, dataB.Velocity.Z)
    else
        local nA, nB = exchangeAxis(dataA.Velocity.Z, dataB.Velocity.Z)
        dataA.Velocity = Vector3.new(dataA.Velocity.X, dataA.Velocity.Y, nA)
        dataB.Velocity = Vector3.new(dataB.Velocity.X, dataB.Velocity.Y, nB)
    end
end

local Engine      = {}
local objects     = {}
local bones       = {}
local rootBones   = {}
local animations  = {}
local constraints = {}

function Engine:AddObject(obj)
    obj.Anchored   = true
    obj.CanCollide = false
    objects[obj] = {
        Velocity  = Vector3.new(0, 0, 0),
        Gravity   = Vector3.new(0, 0, 0),
        Forces    = {},
        Collision = false,
        Floor     = nil,
        OnFloor   = false,
        Mass      = 1,
        Friction  = 0.1,
        Drag      = 0.01,
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

function Engine:SetMass(obj, mass)
    if objects[obj] then
        objects[obj].Mass = math.max(mass, 0.001)
    end
end

function Engine:SetFriction(obj, friction)
    if objects[obj] then
        objects[obj].Friction = math.clamp(friction, 0, 1)
    end
end

function Engine:SetDrag(obj, drag)
    if objects[obj] then
        objects[obj].Drag = math.clamp(drag, 0, 1)
    end
end

function Engine:IsOnFloor(obj)
    return objects[obj] and objects[obj].OnFloor
end

function Engine:AddForce(obj, force)
    if objects[obj] then table.insert(objects[obj].Forces, force) end
end

function Engine:ClearForces(obj)
    if objects[obj] then objects[obj].Forces = {} end
end

function Engine:AddImpulse(obj, impulse)
    if objects[obj] then
        objects[obj].Velocity = objects[obj].Velocity + impulse / objects[obj].Mass
    end
end

function Engine:AddConstraint(id, typeStr, objA, objB, params)
    params = params or {}
    local c = { type = typeStr, objA = objA, objB = objB, params = {} }
    if typeStr == "Distance" then
        c.params.length = params.length or (objA.Position - objB.Position).Magnitude
    elseif typeStr == "Weld" then
        c.params.offset = params.offset or CFrame.new(objB.Position - objA.Position)
    elseif typeStr == "Spring" then
        c.params.restLength = params.restLength or (objA.Position - objB.Position).Magnitude
        c.params.stiffness  = params.stiffness or 50
        c.params.damping    = params.damping   or 5
    end
    constraints[id] = c
end

function Engine:RemoveConstraint(id)
    constraints[id] = nil
end

local function tickConstraints(dt)
    for _, c in pairs(constraints) do
        local a, b = c.objA, c.objB
        local dataA, dataB = objects[a], objects[b]
        local delta = b.Position - a.Position
        local dist  = delta.Magnitude
        if dist < 1e-4 then continue end
        local dir = delta / dist

        if c.type == "Distance" then
            local maxLen = c.params.length
            if dist > maxLen then
                local correction = (dist - maxLen) / 2
                if dataA then
                    a.Position = a.Position + dir * correction
                    local vDot = dataA.Velocity:Dot(dir)
                    if vDot < 0 then dataA.Velocity = dataA.Velocity - dir * vDot end
                end
                if dataB then
                    b.Position = b.Position - dir * correction
                    local vDot = dataB.Velocity:Dot(-dir)
                    if vDot < 0 then dataB.Velocity = dataB.Velocity + dir * vDot end
                end
            end
        elseif c.type == "Weld" then
            if dataB then
                b.Position = a.Position + c.params.offset.Position
                dataB.Velocity = dataA and dataA.Velocity or Vector3.zero
            end
        elseif c.type == "Spring" then
            local stretch = dist - c.params.restLength
            local relVel  = (dataA and dataB) and (dataB.Velocity - dataA.Velocity) or Vector3.zero
            local force   = stretch * c.params.stiffness + relVel:Dot(dir) * c.params.damping
            if dataA then dataA.Velocity = dataA.Velocity + dir *  force * dt end
            if dataB then dataB.Velocity = dataB.Velocity + dir * -force * dt end
        end
    end
end

function Engine:Raycast(origin, direction, params)
    params = params or {}
    local ignoreSet = {}
    for _, v in ipairs(params.ignore or {}) do ignoreSet[v] = true end
    local maxDist = params.maxDist or math.huge
    local dirNorm = direction.Unit
    local bestT, bestObj, bestNormal = maxDist, nil, Vector3.new(0,1,0)

    for obj in pairs(objects) do
        if ignoreSet[obj] then continue end
        local bMin = obj.Position - obj.Size / 2
        local bMax = obj.Position + obj.Size / 2
        local tMin, tMax = -math.huge, math.huge
        local hitNormal, missed = Vector3.zero, false
        local axes = {
            {dir=dirNorm.X, orig=origin.X, mn=bMin.X, mx=bMax.X, n=Vector3.new(-1,0,0)},
            {dir=dirNorm.Y, orig=origin.Y, mn=bMin.Y, mx=bMax.Y, n=Vector3.new(0,-1,0)},
            {dir=dirNorm.Z, orig=origin.Z, mn=bMin.Z, mx=bMax.Z, n=Vector3.new(0,0,-1)},
        }
        for _, ax in ipairs(axes) do
            if math.abs(ax.dir) < 1e-8 then
                if ax.orig < ax.mn or ax.orig > ax.mx then missed=true; break end
            else
                local t1, t2 = (ax.mn-ax.orig)/ax.dir, (ax.mx-ax.orig)/ax.dir
                local n = ax.n
                if t1 > t2 then t1,t2,n = t2,t1,-n end
                if t1 > tMin then tMin,hitNormal = t1,n end
                tMax = math.min(tMax, t2)
                if tMin > tMax then missed=true; break end
            end
        end
        if not missed and tMin >= 0 and tMin < bestT then
            bestT, bestObj, bestNormal = tMin, obj, hitNormal
        end
    end

    if bestObj then
        return { hit=bestObj, distance=bestT, normal=bestNormal, point=origin+dirNorm*bestT }
    end
    return nil
end

function Engine:AddBone(obj, parent)
    obj.Anchored = true; obj.CanCollide = false
    local parentCF = parent and bones[parent].worldCF or obj.CFrame
    local offset   = parentCF:Inverse() * obj.CFrame
    bones[obj] = {
        obj=obj, parent=parent or nil, children={},
        offset=offset, localCF=offset, worldCF=obj.CFrame,
        pinned=false, target=nil, targetOffset=CFrame.new(),
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
        bones[obj].target = target
        bones[obj].targetOffset = offset or CFrame.new()
    end
end

function Engine:SetBonePinned(obj, val)
    if bones[obj] then
        bones[obj].pinned = val
        if val and not objects[obj] then Engine:AddObject(obj) end
    end
end

local function updateBone(boneObj)
    local data = bones[boneObj]
    if not data then return end
    if data.target then
        local targetCF
        if typeof(data.target) == "Instance" then targetCF = data.target.CFrame
        elseif bones[data.target] then targetCF = bones[data.target].worldCF end
        if targetCF then data.worldCF = targetCF * data.targetOffset end
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
    for _, child in ipairs(data.children) do updateBone(child) end
end

function Engine:CreateAnimation(id, keyframes, easing)
    animations[id] = {
        keyframes=keyframes, easing=easing or "Linear",
        playing=false, loop=false, time=0, speed=1,
        length=keyframes[#keyframes].time,
    }
end

function Engine:PlayAnimation(id, loop, speed)
    local anim = animations[id]
    if anim then anim.playing=true; anim.loop=loop or false; anim.speed=speed or 1; anim.time=0 end
end

function Engine:StopAnimation(id)
    if animations[id] then animations[id].playing=false; animations[id].time=0 end
end

local function applyEasing(t, style)
    if style == "EaseIn" then return t*t
    elseif style == "EaseOut" then return 1-(1-t)^2
    elseif style == "EaseInOut" then return t<0.5 and 2*t*t or 1-(-2*t+2)^2/2
    end
    return t
end

local function tickAnimations(dt)
    for _, anim in pairs(animations) do
        if not anim.playing then continue end
        anim.time = anim.time + dt * anim.speed
        if anim.time >= anim.length then
            if anim.loop then anim.time = anim.time % anim.length
            else anim.time=anim.length; anim.playing=false end
        end
        local kf = anim.keyframes
        local kfA, kfB
        for i = 1, #kf-1 do
            if anim.time >= kf[i].time and anim.time <= kf[i+1].time then
                kfA,kfB = kf[i],kf[i+1]; break
            end
        end
        if not kfA then
            for boneObj, cf in pairs(kf[#kf].bones) do
                if bones[boneObj] then bones[boneObj].localCF = cf end
            end
            continue
        end
        local segLen = kfB.time - kfA.time
        local t = applyEasing(segLen > 0 and (anim.time-kfA.time)/segLen or 1, anim.easing)
        for boneObj, cfA in pairs(kfA.bones) do
            local cfB = kfB.bones[boneObj]
            if cfB and bones[boneObj] then bones[boneObj].localCF = cfA:Lerp(cfB, t) end
        end
    end
end

RunService.Heartbeat:Connect(function(dt)
    for obj, data in pairs(objects) do
        local grav = data.Gravity
        if data.OnFloor then grav = Vector3.new(grav.X, 0, grav.Z) end

        local totalForce = Vector3.zero
        for _, f in ipairs(data.Forces) do totalForce = totalForce + f end

        data.Velocity = data.Velocity + (grav + totalForce) * dt

        local drag = 1 - math.clamp(data.Drag * dt * 60, 0, 1)
        data.Velocity = data.Velocity * drag

        if data.OnFloor and data.Friction > 0 then
            local friction = 1 - math.clamp(data.Friction * dt * 60, 0, 1)
            data.Velocity = Vector3.new(
                data.Velocity.X * friction,
                data.Velocity.Y,
                data.Velocity.Z * friction
            )
        end

        obj.Position = obj.Position + data.Velocity * dt
    end

    tickConstraints(dt)

    for obj, data in pairs(objects) do
        if data.Collision then
            for other, otherData in pairs(objects) do
                if obj ~= other and otherData.Collision then
                    if tostring(obj) < tostring(other) then
                        if isColliding(obj, other) then
                            resolveCollision(obj, other, data, otherData)
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
    for _, root in ipairs(rootBones) do updateBone(root) end
end)

return Engine
