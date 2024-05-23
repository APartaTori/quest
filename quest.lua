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

-- Decides the next action based on player proximity, energy, and health.
function makeDecision()
  local player = LatestGameState.Players[ao.id]
  local targetInRange, weakestTarget, minHealth = false, nil, math.huge

  -- Find the weakest player within attack range
  for target, state in pairs(LatestGameState.Players) do
      if target ~= ao.id and inRange(player.x, player.y, state.x, state.y, player.attackRange) then
          if state.health < minHealth then
              minHealth = state.health
              weakestTarget = target
          end
          targetInRange = true
      end
  end

  -- Attack if a weak player is in range and we have sufficient energy
  if player.energy > player.attackEnergyThreshold and targetInRange and weakestTarget then
    print(colors.red .. "Weak player in range. Initiating attack on " .. weakestTarget .. "." .. colors.reset)
    ao.send({Target = Game, Action = "PlayerAttack", TargetID = weakestTarget, AttackEnergy = tostring(player.attackEnergy)})
  else
    -- Seek power-ups or move strategically if no weak player is in range or energy is low
    local powerUpLocation = findNearestPowerUp(player.x, player.y)
    if powerUpLocation and player.energy <= player.energyThreshold then
      print(colors.green .. "Seeking power-up at " .. powerUpLocation .. "." .. colors.reset)
      ao.send({Target = Game, Action = "PlayerMove", Destination = powerUpLocation})
    else
      print(colors.yellow .. "No player in range or insufficient energy. Moving strategically." .. colors.reset)
      local strategicMove = determineStrategicMove(player.x, player.y)
      ao.send({Target = Game, Action = "PlayerMove", Direction = strategicMove})
    end
  end
  InAction = false
end

-- Placeholder for finding the nearest power-up location
function findNearestPowerUp(x, y)
  -- Implementation for finding the nearest power-up
  return "PowerUpLocation" -- Replace with actual logic to determine the location
end

-- Placeholder for determining a strategic move
function determineStrategicMove(x, y)
  -- Implementation for determining a strategic move
  local directionMap = {"Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}
  local strategicIndex = math.random(#directionMap) -- Replace with actual strategy logic
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
