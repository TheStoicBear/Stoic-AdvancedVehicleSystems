-- Constants for driving style flags
local DrivingStyle = {
    StopBeforeVehicles = 1,
    StopBeforePeds = 2,
    AvoidVehicles = 4,
    AvoidEmptyVehicles = 8,
    AvoidPeds = 16,
    AvoidObjects = 32,
    StopAtTrafficLights = 128,
    UseBlinkers = 256,
    AllowWrongWay = 512,
    GoInReverse = 1024,
    TakeShortestPath = 262144,
    IgnoreRoads = 4194304,
    IgnoreAllPathing = 16777216,
    AvoidHighways = 536870912
}

-- Variables to track current state
local currentWaypoint = nil
local lastSpeed = 0
local lastSpeedUpdateTime = 0  -- Initialize lastSpeedUpdateTime

-- Minimum speed threshold in meters per second (5 MPH)
local MIN_SPEED_THRESHOLD = 6.2352  -- 5 MPH in meters per second

-- Maximum speed drop threshold in m/s^2
local MAX_SPEED_DROP_THRESHOLD = 10.0

-- Minimum engine health threshold for damage alert
local MIN_ENGINE_HEALTH_THRESHOLD = 300.0

-- Function to set driving style for a ped
function SetDrivingStyle(ped, drivingStyle)
    Citizen.InvokeNative(0xDACE1BE37D88AF67, ped, drivingStyle)
    print("[DEBUG] SetDrivingStyle: Ped driving style set to " .. drivingStyle)
end

-- Function to handle collision avoidance using raycasts
function HandleCollisionAvoidance(vehicle)
    local ped = GetPedInVehicleSeat(vehicle, -1)  -- Get driver ped
    if ped ~= nil then
        local vehicleSpeed = GetEntitySpeed(vehicle)
        if vehicleSpeed > MIN_SPEED_THRESHOLD then
            local vehiclePosition = GetEntityCoords(vehicle)
            local vehicleForwardVector = GetEntityForwardVector(vehicle)
            
            -- Raycasts
            local frontRaycast = StartShapeTestRay(vehiclePosition.x, vehiclePosition.y, vehiclePosition.z, vehiclePosition.x + vehicleForwardVector.x * 10.0, vehiclePosition.y + vehicleForwardVector.y * 10.0, vehiclePosition.z, 10, vehicle, 0)
            local leftRaycast = StartShapeTestRay(vehiclePosition.x, vehiclePosition.y, vehiclePosition.z, vehiclePosition.x + vehicleForwardVector.x * 10.0 - vehicleForwardVector.y * 5.0, vehiclePosition.y + vehicleForwardVector.y * 10.0 + vehicleForwardVector.x * 5.0, vehiclePosition.z, 10, vehicle, 0)
            local rightRaycast = StartShapeTestRay(vehiclePosition.x, vehiclePosition.y, vehiclePosition.z, vehiclePosition.x + vehicleForwardVector.x * 10.0 + vehicleForwardVector.y * 5.0, vehiclePosition.y + vehicleForwardVector.y * 10.0 - vehicleForwardVector.x * 5.0, vehiclePosition.z, 10, vehicle, 0)
            
            local _, _, _, _, frontEntity = GetShapeTestResult(frontRaycast)
            local _, _, _, _, leftEntity = GetShapeTestResult(leftRaycast)
            local _, _, _, _, rightEntity = GetShapeTestResult(rightRaycast)
            
            -- Draw debug lines for raycasts
            DrawLine(vehiclePosition.x, vehiclePosition.y, vehiclePosition.z, vehiclePosition.x + vehicleForwardVector.x * 10.0, vehiclePosition.y + vehicleForwardVector.y * 10.0, vehiclePosition.z, 255, 0, 0, 255)
            DrawLine(vehiclePosition.x, vehiclePosition.y, vehiclePosition.z, vehiclePosition.x + vehicleForwardVector.x * 10.0 - vehicleForwardVector.y * 5.0, vehiclePosition.y + vehicleForwardVector.y * 10.0 + vehicleForwardVector.x * 5.0, vehiclePosition.z, 0, 255, 0, 255)
            DrawLine(vehiclePosition.x, vehiclePosition.y, vehiclePosition.z, vehiclePosition.x + vehicleForwardVector.x * 10.0 + vehicleForwardVector.y * 5.0, vehiclePosition.y + vehicleForwardVector.y * 10.0 - vehicleForwardVector.x * 5.0, vehiclePosition.z, 0, 0, 255, 255)

            if frontEntity ~= 0 then
                -- Perform emergency braking
                TaskVehicleTempAction(ped, vehicle, 1, 1000)
                print("[DEBUG] HandleCollisionAvoidance: Emergency brake activated due to vehicle in front.")
            elseif leftEntity ~= 0 then
                -- Steer right to avoid obstacle on the left
                Citizen.InvokeNative(0x5C9B84BD7D31D908, ped, vehicle, rightEntity)
                print("[DEBUG] HandleCollisionAvoidance: Steering right to avoid obstacle on the left.")
            elseif rightEntity ~= 0 then
                -- Steer left to avoid obstacle on the right
                Citizen.InvokeNative(0x5C9B84BD7D31D908, ped, vehicle, leftEntity)
                print("[DEBUG] HandleCollisionAvoidance: Steering left to avoid obstacle on the right.")
            end
        end
    end
end

-- Function to play beep sound when obstacle is detected
function PlayObstacleBeep()
    PlaySoundFrontend(-1, "Out_Of_Area", "DLC_Lowrider_Relay_Race_Sounds", false)
    print("[DEBUG] PlayObstacleBeep: Beep sound played due to obstacle detected.")
end

-- Function for lane assistance
function LaneAssistance(vehicle)
    local ped = GetPedInVehicleSeat(vehicle, -1)  -- Get driver ped
    if ped ~= nil then
        local currentHeading = GetEntityHeading(vehicle)
        local currentLaneHeading = math.floor(currentHeading / 10) * 10  -- Round heading to nearest 10 degrees for lane alignment
        SetEntityHeading(vehicle, currentLaneHeading)
    end
end


-- Function to check if there's an obstacle ahead using raycasts
function IsObstacleAhead(vehicle)
    local vehiclePosition = GetEntityCoords(vehicle)
    local vehicleForwardVector = GetEntityForwardVector(vehicle)

    -- Raycast in front of the vehicle
    local frontRaycast = StartShapeTestRay(vehiclePosition.x, vehiclePosition.y, vehiclePosition.z, 
        vehiclePosition.x + vehicleForwardVector.x * 10.0, vehiclePosition.y + vehicleForwardVector.y * 10.0, vehiclePosition.z, 10, vehicle, 0)
    local _, _, _, _, frontEntity = GetShapeTestResult(frontRaycast)

    -- Draw debug line for front raycast
    DrawLine(vehiclePosition.x, vehiclePosition.y, vehiclePosition.z,
        vehiclePosition.x + vehicleForwardVector.x * 10.0, vehiclePosition.y + vehicleForwardVector.y * 10.0, vehiclePosition.z, 255, 0, 0, 255)

    if frontEntity ~= 0 then
        return true
    end

    return false
end

-- local ALERT_INTERVAL = 240000 -- 4 minutes in milliseconds
local ALERT_INTERVAL = 4000 -- 4 minutes in milliseconds
-- Track last alert time and vehicle
local lastAlertTime = 0
local lastVehicle = nil

-- Function to send accident details to chat
function SendAccidentDetails(speed, location, vehicleModel)
    local message = string.format("^1Accident Detected:^7 Vehicle Model: %s, Speed: %.2f mph, Location: %s", vehicleModel, speed * 2.23694, location)
    SendNotification(message, {255, 0, 0})
    DebugPrint("[DEBUG] SendAccidentDetails: Accident details sent to chat.")
end

-- Function to send OnStar alert for sudden speed drop
function SendOnStarAlert(speedDrop)
    local message = string.format("^1OnStar Alert:^7 Sudden speed drop detected: %.2f m/s^2", speedDrop)
    SendNotification(message, {255, 255, 0})
    DebugPrint("[DEBUG] SendOnStarAlert: OnStar alert sent to chat.")
end

-- Function to check if there's an obstacle ahead using raycasts
function IsObstacleAhead(vehicle)
    local pos = GetEntityCoords(vehicle)
    local fwd = GetEntityForwardVector(vehicle)
    local result = StartShapeTestRay(pos.x, pos.y, pos.z, pos.x + fwd.x * 10.0, pos.y + fwd.y * 10.0, pos.z, 10, vehicle, 0)
    local _, _, _, _, entityHit = GetShapeTestResult(result)
    return entityHit ~= 0
end

-- Function to send OnStar alert for vehicle damage
function SendVehicleDamageAlert(vehicle)
    Citizen.Wait(5000)  -- Check every second
    local engineHealth = GetVehicleEngineHealth(vehicle)
    local wheelCount = GetVehicleNumberOfWheels(vehicle)
    local isWheelBroken = false
    local isFrontBumperBroken = false
    local isRearBumperBroken = false
    local isDoorDamaged = false
    local isWindowBroken = IsVehicleWindowIntact(vehicle, 0) == false
    local isEngineOnFire = IsVehicleEngineOnFire(vehicle)
    
    -- Debug prints for initial values
    print(string.format("[DEBUG] SendVehicleDamageAlert: Engine Health: %.2f", engineHealth))
    print(string.format("[DEBUG] SendVehicleDamageAlert: Wheel Count: %d", wheelCount))
    print(string.format("[DEBUG] SendVehicleDamageAlert: Is Window Broken: %s", tostring(isWindowBroken)))
    print(string.format("[DEBUG] SendVehicleDamageAlert: Is Engine On Fire: %s", tostring(isEngineOnFire)))

    -- Check each wheel for damage
    for i = 0, wheelCount - 1 do
        if IsVehicleTyreBurst(vehicle, i, false) then
            isWheelBroken = true
            print(string.format("[DEBUG] SendVehicleDamageAlert: Wheel %d is broken", i))
            break
        end
    end
    
    -- Check bumpers
    isFrontBumperBroken = IsVehicleBumperBrokenOff(vehicle, true)
    isRearBumperBroken = IsVehicleBumperBrokenOff(vehicle, false)
    
    -- Debug prints for bumpers
    print(string.format("[DEBUG] SendVehicleDamageAlert: Is Front Bumper Broken: %s", tostring(isFrontBumperBroken)))
    print(string.format("[DEBUG] SendVehicleDamageAlert: Is Rear Bumper Broken: %s", tostring(isRearBumperBroken)))
    
    -- Check doors
    for i = 0, 5 do
        if IsVehicleDoorDamaged(vehicle, i) then
            isDoorDamaged = true
            print(string.format("[DEBUG] SendVehicleDamageAlert: Door %d is damaged", i))
            break
        end
    end

    -- Check if any damage criteria are met
    if engineHealth < MIN_ENGINE_HEALTH_THRESHOLD or
       isWheelBroken or
       isWindowBroken or
       isFrontBumperBroken or
       isRearBumperBroken or
       isDoorDamaged or
       isEngineOnFire then

        local message = "OnStar Alert: Vehicle damage detected: "

        if engineHealth < MIN_ENGINE_HEALTH_THRESHOLD then
            message = message .. string.format("Engine health at %.2f, ", engineHealth)
        end

        if isWheelBroken then
            message = message .. "Wheel(s) broken, "
        end

        if isFrontBumperBroken then
            message = message .. "Front bumper broken, "
        end

        if isRearBumperBroken then
            message = message .. "Rear bumper broken, "
        end

        if isDoorDamaged then
            message = message .. "Door(s) damaged, "
        end

        if isWindowBroken then
            message = message .. "Window(s) broken, "
        end

        if isEngineOnFire then
            message = message .. "Engine on fire, "
        end

        -- Remove trailing comma and space
        message = string.gsub(message, ", $", "")

        -- Define style for the notification
        local style = {
            backgroundColor = '#1E1F22',
            color = '#FFFFFF',
            icon = 'exclamation-circle',
            iconColor = '#FFFFFF',
            iconAnimation = 'spin',
            alignIcon = 'top',
            duration = 10000,  -- 10 seconds
            position = 'top-right'
        }

        -- Send the notification using lib.notify
        lib.notify({
            title = 'OnStar Alert',
            description = message,
            type = 'error',
            style = style
        })

        -- Debug print after sending alert
        print("[DEBUG] SendVehicleDamageAlert: Vehicle damage alert sent to chat.")
    else
        print("[DEBUG] SendVehicleDamageAlert: No significant damage detected.")
    end
end

-- Function for debug printing with formatting
function DebugPrint(message)
    print(message)
end

-- Function to send notifications to a system (replace with actual implementation)
function SendNotification(message, color)
    TriggerEvent('chat:addMessage', {
        color = color,
        multiline = true,
        args = { message }
    })
end

-- Thread to continuously check the car for damage
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(10000) -- Check every 5 seconds, adjust as needed
        local playerPed = PlayerPedId()
        if IsPedInAnyVehicle(playerPed, false) then
            local vehicle = GetVehiclePedIsIn(playerPed, false)
            local currentTime = GetGameTimer()

            -- Check if the alert needs to be sent
            if vehicle == lastVehicle and (currentTime - lastAlertTime) < ALERT_INTERVAL then
                print("[DEBUG] Vehicle damage alert already sent recently.")
            else
                SendVehicleDamageAlert(vehicle)
                lastAlertTime = currentTime
                lastVehicle = vehicle
            end
        else
            -- Reset lastVehicle if player is not in a vehicle
            lastVehicle = nil
        end
    end
end)

-- Main loop
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)  -- Check every second

        local playerPed = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(playerPed, false)
        
        if vehicle ~= 0 then
            HandleCollisionAvoidance(vehicle)
            -- LaneAssistance(vehicle)
            
            local currentSpeed = GetEntitySpeed(vehicle)
            local currentTime = GetGameTimer()

            if lastSpeedUpdateTime ~= 0 then
                local timeDelta = (currentTime - lastSpeedUpdateTime) / 1000.0
                local speedDrop = (lastSpeed - currentSpeed) / timeDelta

                if speedDrop > MAX_SPEED_DROP_THRESHOLD then
                    SendOnStarAlert(speedDrop)
                end
            end

            lastSpeed = currentSpeed
            lastSpeedUpdateTime = currentTime

            if IsVehicleDamaged(vehicle) then
                Citizen.Wait(10000)  -- Check every second
                SendVehicleDamageAlert(vehicle)
            end

            if currentSpeed < MIN_SPEED_THRESHOLD and lastSpeed >= MIN_SPEED_THRESHOLD then
                local location = GetEntityCoords(vehicle)
                local vehicleModel = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
                SendAccidentDetails(lastSpeed, string.format("X: %.2f, Y: %.2f, Z: %.2f", location.x, location.y, location.z), vehicleModel)
            end

            if IsObstacleAhead(vehicle) then
                PlayObstacleBeep()
            end
        end
    end
end)