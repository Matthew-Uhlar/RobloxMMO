-- Builds the production world (world.server.lua) headlessly with real Roblox
-- datatypes and instances, with the same deterministic doubles verify-world.luau
-- uses, plus a home for player 1 and a sample crew haven (CoopId "crew-1").
-- Used by verify-map.luau and tools/render-ui.luau (Sky Chart miniature,
-- minimap plates). Run from the project directory.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local W = {}
local function signal()
	local listeners = {}
	return {
		Connect = function(_, callback)
			local connection = { Connected = true }
			function connection:Disconnect() self.Connected = false end
			table.insert(listeners, { callback, connection })
			return connection
		end,
		Fire = function(_, ...)
			for _, listener in listeners do
				if listener[2].Connected then listener[1](...) end
			end
		end,
	}
end
local promptSignals = {}
local built
function W.build()
	if built then return built end
	pcall(roblox.implementProperty, "ProximityPrompt", "Triggered", function(prompt)
		if not promptSignals[prompt] then promptSignals[prompt] = signal() end
		return promptSignals[prompt]
	end)
	local players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end }
	local Data = luau.load(fs.readFile("shared/GameData.lua"))()
	local dataModule = { Name = "AetherData" }
	local services = {
		Players = players,
		Lighting = roblox.Instance.new("Lighting"),
		CollectionService = { AddTag = function() end },
		ReplicatedStorage = { WaitForChild = function(_, name) return if name == "AetherData" then dataModule else nil end },
		ServerStorage = { FindFirstChild = function() return nil end },
	}
	local world = roblox.Instance.new("Workspace")
	local environment = {
		game = { GetService = function(_, name) return services[name] end },
		workspace = world, Instance = roblox.Instance, Vector3 = Vector3, Vector2 = roblox.Vector2, CFrame = CFrame, Color3 = roblox.Color3,
		UDim2 = roblox.UDim2, Font = roblox.Font, Enum = roblox.Enum,
		task = {
			spawn = function(fn, ...)
				local co = coroutine.create(fn)
				assert(coroutine.resume(co, ...))
				return co
			end,
			wait = function() return coroutine.yield() end,
		},
		NumberRange = roblox.NumberRange, NumberSequence = roblox.NumberSequence, ColorSequence = roblox.ColorSequence,
		require = function(module) assert(module == dataModule, "world requires only AetherData") return Data end,
	}
	-- Lune does not synthesize BasePart.Position from CFrame as the engine does.
	local source = fs.readFile("world.server.lua"):gsub("plans%.Position", "plans.CFrame.Position")
	luau.load(source, { environment = environment, injectGlobals = true })()
	-- A home for player 1 (the UI harness player).
	local owner = { UserId = 1, CharacterAdded = signal(), attributes = {} }
	function owner:GetAttribute(key) return self.attributes[key] end
	function owner:GetAttributeChangedSignal() return signal() end
	function owner:SetAttribute(key, value) self.attributes[key] = value end
	players.PlayerAdded:Fire(owner)
	-- A crew haven stand-in for CoopId "crew-1": its meadow and a few trees.
	local archipelago = world:FindFirstChild("AetherIsles")
	local crew = roblox.Instance.new("Model")
	crew.Name = "CrewHaven_test"
	crew:SetAttribute("CoopId", "crew-1")
	crew:SetAttribute("IslandCenter", Vector3.new(-260, 0, -620))
	crew:SetAttribute("IslandRadius", 46)
	local function part(name, size, cf, color, shape)
		local p = roblox.Instance.new("Part")
		p.Name, p.Size, p.CFrame, p.Color = name, size, cf, roblox.Color3.fromHex(color)
		if shape then p.Shape = shape end
		p.Parent = crew
		return p
	end
	local cyl, ball = roblox.Enum.PartType.Cylinder, roblox.Enum.PartType.Ball
	local up = CFrame.Angles(0, 0, math.pi / 2)
	part("Meadow", Vector3.new(0.5, 92, 92), CFrame.new(-260, -0.25, -620) * up, "86AD7A", cyl)
	part("Floating foundation", Vector3.new(6, 93, 93), CFrame.new(-260, -3.6, -620) * up, "485565", cyl)
	part("Island underside", Vector3.new(30, 78, 78), CFrame.new(-260, -21, -620) * up, "3F4A58", cyl)
	for i, o in ipairs({ { 30, -20 }, { -34, 10 }, { 26, 30 }, { -10, 36 } }) do
		part("Trunk", Vector3.new(6, 1.1, 1.1), CFrame.new(-260 + o[1], 3, -620 + o[2]) * up, "6B4E37", cyl)
		part("Canopy", Vector3.new(6.8, 6.8, 6.8), CFrame.new(-260 + o[1], 7.2, -620 + o[2]), if i % 2 == 0 then "5E8B57" else "7FAA62", ball)
	end
	crew.Parent = archipelago
	-- Lune keeps Position separate from CFrame: mirror it so client code that
	-- reads part.Position (nav.client.lua) sees the engine's value.
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") then d.Position = d.CFrame.Position end
	end
	built ={ world = world, islands = world:FindFirstChild("Islands"), archipelago = archipelago, Data = Data, players = players }
	return built
end
-- A table standing in for Workspace in a client script's environment.
function W.workspace(new)
	local b = W.build()
	return {
		CurrentCamera = new and new("Camera") or nil,
		FindFirstChild = function(_, name) return b.world:FindFirstChild(name) end,
	}
end
return W
