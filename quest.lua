-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
Game = Game or nil
InAction = InAction or false

Logs = Logs or {}

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

function makeDecision()
    local player = LatestGameState.Players[ao.id]
    local targetInRange, weakestTarget, minHealth = false, nil, math.huge

    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id and inRange(player.x, player.y, state.x, state.y, player.attackRange) then
            local distance = calculateDistance(player.x, player.y, state.x, state.y)
            local healthToDistanceRatio = state.health / distance

            if state.health < minHealth and healthToDistanceRatio < 0.5 then
                minHealth = state.health
                weakestTarget = target
            end
            targetInRange = true
        end
    end

    local energyThreshold = calculateDynamicEnergyThreshold(player)

    if player.energy > energyThreshold and targetInRange and weakestTarget then
        print(colors.red .. "Weak player in range. Initiating attack on " .. weakestTarget .. "." .. colors.reset)
        ao.send({Target = Game, Action = "PlayerAttack", TargetID = weakestTarget, AttackEnergy = tostring(player.attackEnergy)})
    else
        local strategicMove = makeStrategicDecision(player)
        print(colors.yellow .. "No player in range or insufficient energy. Moving strategically: " .. strategicMove .. colors.reset)
        ao.send({Target = Game, Action = "PlayerMove", Direction = strategicMove})
    end
end

function calculateDistance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1)^2 + (y2 - y1)^2)
end

function calculateDynamicEnergyThreshold(player)
    local baseThreshold = player.attackEnergyThreshold
    local healthFactor = player.health / player.maxHealth
    local opponentCount = countNearbyOpponents(player)

    return baseThreshold * healthFactor * (1 + opponentCount * 0.1)
end

function countNearbyOpponents(player)
    local count = 0
    for _, state in pairs(LatestGameState.Players) do
        if state ~= ao.id and inRange(player.x, player.y, state.x, state.y, player.attackRange) then
            count = count + 1
        end
    end
    return count
end

function makeStrategicDecision(player)
    local directionMap = {"Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}
    local strategicIndex = math.random(#directionMap)
    return directionMap[strategicIndex]
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true
      -- print("Getting game state...")
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then
      InAction = true
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then 
      InAction = false
      return 
    end
    print("Deciding next action.")
    makeDecision()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then
      InAction = true
      local playerState = LatestGameState.Players[ao.id]
      local attackerState = LatestGameState.Players[msg.AttackerID]

      -- Check if the player's and attacker's energy levels are defined
      if playerState.energy == undefined or attackerState.energy == undefined then
        print(colors.red .. "Unable to read energy levels." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy levels."})
      elseif playerState.energy == 0 then
        print(colors.red .. "Player has insufficient energy to return attack." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        -- Calculate the energy to use for the counterattack based on the player's strategy
        local counterAttackEnergy = math.min(playerState.energy, attackerState.energy * playerState.counterAttackMultiplier)
        print(colors.red .. "Returning attack with energy: " .. counterAttackEnergy .. "." .. colors.reset)
        ao.send({Target = Game, Action = "PlayerAttack", TargetID = msg.AttackerID, AttackEnergy = tostring(counterAttackEnergy)})
      end
      InAction = false
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)
