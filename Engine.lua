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

local Engine = {}
local objects = {}

function Engine:AddObject(obj)
    obj.Anchored = true
    obj.CanCollide = false

    objects[obj] = {
        Velocity  = Vector3.new(0, 0, 0),
        Gravity   = Vector3.new(0, 0, 0),
        Collision = false,
        Floor     = nil,
        OnFloor   = false
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
                obj.Position = Vector3.new(
                    obj.Position.X,
                    val + halfH,
                    obj.Position.Z
                )
                objects[obj].Velocity = Vector3.new(0, 0, 0)
            end
        end
    end
end

function Engine:IsOnFloor(obj)
    return objects[obj] and objects[obj].OnFloor
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
            for other, _ in pairs(objects) do
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
                obj.Position = Vector3.new(
                    obj.Position.X,
                    floorY + halfH,
                    obj.Position.Z
                )

                if data.Velocity.Y < 0 then
                    data.Velocity = Vector3.new(data.Velocity.X, 0, data.Velocity.Z)
                end

                data.OnFloor = math.abs(data.Velocity.Y) < 0.5
            else
                data.OnFloor = false
            end
        end
    end
end)

return Engine
