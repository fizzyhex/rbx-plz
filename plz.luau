--[=[
	## plz

	my super-focused ui library, plz.
]=]
local plz = {}

const RunService = game:GetService("RunService")
const STEP_SIGNAL = RunService:IsServer() and RunService.Heartbeat or RunService.RenderStepped

local evy = {}

-- plz.changed keys: "changed:Text" <-> "Text". ':' can't appear in a property name
local changed_keys: { [string]: string } = {}
local changed_properties: { [string]: string } = {}

export type EvyContext = {
	-- { [Instance]: { [event_name: string]: { pack() } } }
	mapping: { [Instance]: { [string]: { any } } },
	-- { [Instance]: { [event_name: string]: RBXScriptConnection } }
	connections: { [Instance]: { [string]: RBXScriptConnection } },
	-- { [Instance]: { [event_name: string]: true } }
	accessed_this_frame: { [Instance]: { [string]: true } },
	-- cleared every frame
	listeners: { [Instance]: { [string]: { (...any) -> () } } },
	-- last value plz wrote or reported, for properties with plz.changed listeners
	known: { [Instance]: { [string]: any } },
}

do
	function evy.context()
		local new_context: EvyContext = {
			mapping = {},
			connections = {},
			accessed_this_frame = {},
			listeners = {},
			known = {},
		}

		return new_context
	end

	function evy.touch(ctx: EvyContext, instance: Instance, event: string)
		ctx.accessed_this_frame[instance] = ctx.accessed_this_frame[instance] or {}
		ctx.accessed_this_frame[instance][event] = true

		ctx.mapping[instance] = ctx.mapping[instance] or {}

		if ctx.mapping[instance][event] then
			return
		end

		ctx.connections[instance] = ctx.connections[instance] or {}
		ctx.listeners[instance] = ctx.listeners[instance] or {}
		ctx.listeners[instance][event] = ctx.listeners[instance][event] or {}

		evy.collect(ctx, instance, event)
	end

	function evy.collect(ctx: EvyContext, instance: Instance, event: string)
		if ctx.connections[instance][event] then
			return -- don't register twice
		end
		
		local packs = {}
		--print(`connecting to {instance}.{event}`)

		local property = changed_properties[event]

		if property then
			local target = instance :: any
			-- throws for a bad property name before anything is recorded
			local signal = instance:GetPropertyChangedSignal(property)
			local known = ctx.known[instance] or {}
			ctx.known[instance] = known
			known[property] = target[property]

			ctx.connections[instance][event] = signal:Connect(function()
				local value = target[property]

				-- plz's own writes echoing back, or a value already reported
				if value == known[property] then
					return
				end

				known[property] = value
				table.insert(packs, table.pack(value))
			end)
		else
			local signal = (instance :: Instance & { [string]: unknown })[event]
			assert(typeof(signal) == "RBXScriptSignal")

			ctx.connections[instance][event] = (signal::any):Connect(function(...)
				table.insert(packs, table.pack(...))
			end)
		end

		-- recorded last, so a bad event name throws again next frame instead of going quiet
		ctx.mapping[instance][event] = packs
	end

	function evy.add_listener(ctx: EvyContext, instance: Instance, event: string, callback: (...any) -> ())
		table.insert(ctx.listeners[instance][event], callback)
	end

	function evy.flush(ctx: EvyContext, complete: boolean)
		for instance, event_pack_map in ctx.mapping do
			local access_grants = ctx.accessed_this_frame[instance]

			if not next(access_grants) then
				if not complete then
					-- the frame failed before reaching this instance; keep it for the next one
					continue
				end

				ctx.mapping[instance] = nil
				ctx.listeners[instance] = nil
				
				for _, connection in ctx.connections[instance] do
					--print(`disconnecting an event from {instance}`)
					connection:Disconnect()
				end

				ctx.known[instance] = nil
				ctx.accessed_this_frame[instance] = nil
				ctx.connections[instance] = nil
				continue
			end

			table.clear(ctx.accessed_this_frame[instance])

			-- future: we could clean-up non-accessed keys here too, but the use-case is narrow.

			for event_name, packs in event_pack_map do
				for _, listener in ctx.listeners[instance][event_name] do
					for _, pack in packs do
						listener(table.unpack(pack, pack.n))
					end
				end

				table.clear(ctx.listeners[instance][event_name])
				table.clear(packs)
			end
		end
	end
end

local templates: { Instance } = {}
local changes: { [number]: { [string]: { any } } } = {}

const CHUNK_SIZE = 10000
local latest_allocation = 0

type Allocation<T = any> = { read _T: T }
type Unpack<T> = index<T, "_T">

type EventKey<T...> = { _is_event_key: true, _listener: (T...) -> () }

export type Pen = {
	render: (self: Pen) -> number,
	destroy: (self: Pen) -> (),
	node: <T>(self: Pen, allocation: Allocation<T>) -> Node<T>,
	instance: <T>(self: Pen, node: { read _allocation: Allocation<T> }) -> T,
}

export type Node<T=Instance, A...=...unknown> = T & {
	read _allocation: Allocation<T>,
} & {
	[EventKey<A...>]: (A...) -> ()
}

export type PenCtx = {
	-- this pen's instances by slot id; pens share allocations, not instances
	pool: { [number]: Instance & {} },
    last_changes: { [number]: { [string]: true } },
	queue: { Node },
	dirty: { [Instance & {}]: number },
	references: { [Node]: number },
	free_elements: {Node},
	event_context: EvyContext
}

local pen = {}
pen.__index = pen

local NULL = newproxy(true)
getmetatable(NULL).__tostring = function()
	return "NULL"
end

local function nullable<T>(x: T): T?
	return if x == nil then NULL else x
end

local function unpack_nullable<T>(x: T): T?
	return if x == NULL then nil else x
end

local function get_id(allocation: Allocation<any>, offset: number)
    return allocation :: Unpack<Allocation> + offset
end

local function allocation_from_id(id: number)
	return id - id % CHUNK_SIZE
end

local function get_instance(ctx: PenCtx, allocation: Allocation<any>, offset: number): Instance & {}
	assert(offset < CHUNK_SIZE, `Offset > CHUNK_SIZE ({CHUNK_SIZE})`)
	local id = get_id(allocation, offset)
	local match = ctx.pool[id]

	if not match then
		local new = Instance.fromExisting(templates[allocation :: Unpack<Allocation>])
		ctx.pool[id] = new
		return new
	end

	return match
end

local function get_defaults_entry(allocation: Allocation<any> | number)
	local id = allocation :: Unpack<Allocation>
	local match = changes[id]

	if not match then
		changes[id] = {}
		return changes[id]
	end

	return match
end

function pen.node<T>(ctx: PenCtx, allocation: Allocation<T>, hook): Node<T>
	local element = table.remove(ctx.free_elements) or {} :: Node<T>
 	element._allocation = allocation
	table.insert(ctx.queue, element)
	ctx.references[element] = #ctx.queue
	return element
end

--[=[
	Returns the instance a node renders to this frame, as of the last render.
	Use it to read properties or call methods. Avoid writing properties plz
	doesn't manage, since the instance is reused by other nodes later. The node
	can sit on a different instance next frame, so look it up each frame.
]=]
function pen.instance<T>(ctx: PenCtx, node: Node<T>): T
	local offset = ctx.references[node]
	assert(offset, "node isn't queued in this pen this frame")
	return get_instance(ctx, node._allocation, offset) :: any
end

local function apply(ctx: PenCtx): number
	local updates = 0
	local updated = {}

	for offset, element in ctx.queue do
		local id = get_id(element._allocation, offset)
		local instance = get_instance(ctx, element._allocation, offset)
		local defaults = get_defaults_entry(element._allocation)
        local last = ctx.last_changes[id] or {} :: keyof<index<PenCtx, "last_changes">>

		-- tracked before writing, so a write that throws can't leave untracked properties behind
		ctx.dirty[instance] = id :: Unpack<Allocation>
		ctx.last_changes[id] = last
		-- only set for instances with plz.changed listeners
		local known = ctx.event_context.known[instance]

		for key, value in element :: Node<any> do
			if key == "_allocation" then
				continue
			end

			if value == unpack_nullable(last[key]) then
				-- save the roblox api c boundary trip
				continue
			end

			-- this means that all tables are treated as references.
			-- that's OK, because the user should never be adding a table to
			-- a node otherwise
			if typeof(value) == "table" then
                local reference_offset = ctx.references[value]
                assert(reference_offset)
				assert(value._allocation, `missing allocation! {key} {reference_offset}`)

				if defaults[key] == nil then
					defaults[key] = nullable(instance[key])
					--print(`learnt a new default for {key}`, defaults[key])
				end

				local resolution = get_instance(ctx, value._allocation, reference_offset)

				if last[key] ~= resolution then
					if known then
						known[key] = resolution
					end

					instance[key] = resolution
					last[key] = resolution
					updates += 1
				end
			elseif typeof(value) == "function" then
				evy.touch(ctx.event_context, instance, key)
				evy.add_listener(ctx.event_context, instance, key, value)
				known = ctx.event_context.known[instance]
				continue
            else
				if defaults[key] == nil then
					defaults[key] = nullable(instance[key])
					--print(`learnt a new default for {key}`, defaults[key])
				end

				if known then
					known[key] = value
				end

                instance[key] = value
				last[key] = nullable(value)
				updates += 1
			end
		end

		updated[instance] = true

        for key, value in last do
			if (element :: Node<unknown> & {})[key] == nil and defaults[key] ~= nil then
				if known then
					known[key] = unpack_nullable(defaults[key])
				end

				instance[key] = unpack_nullable(defaults[key])
				last[key] = nil
			end
        end
	end

	for instance, id in ctx.dirty do
		local allocation = allocation_from_id(id)

		if updated[instance] == nil then
			-- restore all defaults
			for key, value in get_defaults_entry(allocation) do
				instance[key] = unpack_nullable(value)
			end

			ctx.dirty[instance] = nil
			ctx.last_changes[id] = nil
		end
	end

	return updates
end

function pen.render(ctx: PenCtx)
	local ok, updates = xpcall(apply, debug.traceback, ctx)

	-- recycle the frame even if a write threw, otherwise its nodes stay queued
	-- and every later frame repeats the failing write
	for index = 1, #ctx.queue do
		local element = ctx.queue[index]
		table.clear(element)
		table.insert(ctx.free_elements, element)
	end

	table.clear(ctx.queue)
	table.clear(ctx.references)

	evy.flush(ctx.event_context, ok)

	if not ok then
		error(updates, 0)
	end

	return updates
end

--[=[
	Destroys the pen's instances and disconnects its events. Drawing with the pen
	afterwards starts from scratch.
]=]
function pen.destroy(ctx: PenCtx)
	for _, connections in ctx.event_context.connections do
		for _, connection in connections do
			connection:Disconnect()
		end
	end

	for _, instance in ctx.pool do
		instance:Destroy()
	end

	table.clear(ctx.pool)
	table.clear(ctx.dirty)
	table.clear(ctx.last_changes)
	ctx.event_context = evy.context()
end

assert(allocation_from_id(CHUNK_SIZE) == CHUNK_SIZE)
assert(allocation_from_id(CHUNK_SIZE * 2) == CHUNK_SIZE * 2)
assert(allocation_from_id((CHUNK_SIZE * 2) + math.floor(CHUNK_SIZE / 2)) == CHUNK_SIZE * 2)

function plz.pen()
    local ctx: PenCtx = {
        pool = {},
        last_changes = {},
        queue = {},
		dirty = {},
		references = {},
		free_elements = table.create(500) :: index<PenCtx, "free_elements">,
		event_context = evy.context(),
    }

    return setmetatable(ctx, pen) :: Pen
end

--[=[
	Creates a spot for the provided Instance in the pool.
]=]
function plz.allocate<T>(instance: T & Instance)
	latest_allocation += CHUNK_SIZE
	templates[latest_allocation] = instance
	return (latest_allocation :: any) :: Allocation<T>
end

function plz.event<T...>(node: Node, key: RBXScriptSignal<T...>, fn: (T...) -> ())
	local s = if typeof(key) == "string" then key else tostring(key):sub(8)
	node[s] = fn
end

--[=[
	Listens for changes to a property of the node's instance made by anything
	other than plz: typing into a TextBox, scrolling, layout changing
	AbsoluteSize. Changes are buffered like events and delivered during the next
	render, one call per new value.
]=]
function plz.changed(node: Node, property: string, fn: (value: any) -> ())
	local key = changed_keys[property]

	if not key then
		key = `changed:{property}`
		changed_keys[property] = key
		changed_properties[key] = property
	end

	node[key] = fn
end

function plz.loop(pen: Pen, renderer: (delta_time: number, updates: number) -> (), loop)
	local last_updates = 0

	local connection = STEP_SIGNAL:Connect(function(delta_time)
		renderer(delta_time, last_updates)
		last_updates = pen:render()
	end)
	
	return function()
		connection:Disconnect()
	end
end

return plz
