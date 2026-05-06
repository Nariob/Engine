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
    local overlap = (obj.Size + other.Size) / 2 - Vector3.new(math.abs(delta.X), math.abs(delta.Y), math.abs(delta.Z))

    if overlap.X < overlap.Y and overlap.X < overlap.Z then
        local direction = math.sign(delta.X)
        obj.Position = obj.Position + Vector3.new(overlap.X * direction, 0, 0)
        data.velocity = Vector3.new(0, data.velocity.Y, data.velocity.Z)

    elseif overlap.Y < overlap.Z then
        local direction = math.sign(delta.Y)
        obj.Position = obj.Position + Vector3.new(0, overlap.Y * direction, 0)
        data.velocity = Vector3.new(data.velocity.X, 0, data.velocity.Z)

    else
        local direction = math.sign(delta.Z)
        obj.Position = obj.Position + Vector3.new(0, 0, overlap.Z * direction)
        data.velocity = Vector3.new(data.velocity.X, data.velocity.Y, 0)
    end
end

local Engine = {}

local objects = {}

function Engine:AddObject(obj)
    objects[obj] = {
        Velocity = Vector3.new(0, 0, 0),
        Gravity = Vector3.new(0, 0, 0),
        Collision = false,
        Floor = 0
    }
end

function Engine:SetVelocity(obj, vel)
    if objects[obj] then
        objects[obj].Velocity = vel
    end
end

function Engine:SetGravity(obj, grav)
    if objects[obj] then
        objects[obj].Gravity = grav
    end
end

function Engine:SetCollision(obj, val)
    if objects[obj] then
        objects[obj].Collision = val
    end
end

function Engine:SetFloor(obj, val)
    if objects[obj] then
        objects[obj].Floor = val
    end
end

RunService.Heartbeat:Connect(function(dt)
    for obj, data in pairs(objects) do
        data.Velocity = data.Velocity + data.Gravity * dt
        obj.Position = obj.Position + data.Velocity * dt

        local halfHeight = obj.Size.Y / 2
        local floorY = data.Floor

        if obj.Position.Y - halfHeight < floorY then
            obj.Position = Vector3.new(
                obj.Position.X,
                floorY + halfHeight,
                obj.Position.Z
            )

            if data.Velocity.Y < 0 then
                data.Velocity = Vector3.new(
                    data.Velocity.X,
                    0,
                    data.Velocity.Z
                )
            end
        end
    end

    for obj, data in pairs(objects) do
        if data.Collision then
            for other, otherData in pairs(objects) do
                if obj ~= other and otherData.Collision then
                    if tostring(obj) < tostring(other) then
                        if isColliding(obj, other) then
                            resolveCollision(obj, other, data)
                        end
                    end
                end
            end
        end
    end
end)

return Engine