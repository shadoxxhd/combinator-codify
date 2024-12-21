-- Lookup table for sorting table keys in a human readable order
-- e.g. signal comparator signal, signal comparator constant, etc.
local combinator_table_key_order = {
  -- decider combinator conditions
  compare_type = 1,
  first_signal = 2,
  first_signal_networks = 3,
  comparator = 4,   -- also constant combinator signal
  second_signal = 5,
  second_signal_networks = 6,
  -- decider combinator outputs
  signal = 2,
  networks = 3,
  -- arithmetic combinator
  first_constant = 2,
  operation = 4,   -- also selector combinator
  second_constant = 5,
  output_signal = 7,
  -- signal
  name = 1,
  quality = 2,
  count = 5,   -- after comparator
  -- signal networks
  red = 1,
  green = 2,
}
local function sort_by_key_order(a, b)
  local oa = combinator_table_key_order[a]
  local ob = combinator_table_key_order[b]
  if oa and ob then return oa < ob end
  if oa then return true end
  if ob then return false end
  return a < b
end
local function sort_combinator_table(keys, orig_table)
  table.sort(keys, sort_by_key_order)
end

--- used by serpent to output serialized lua tables
--- this format function collapses certain table keys to single lines for easier reading and editing
local function format_combinator_table(tag, head, body, tail)
  local out = head .. body .. tail
  if tag:match "signal = $" or tag:match "_signal_networks = $" or tag == "networks = " then
    -- collapse to one line
    out = out:gsub("\n%s+", "")
    -- space out various punctuation
    out = out:gsub("{", "{ ")
    out = out:gsub("}", " }")
    out = out:gsub(",", ", ")
  end
  return tag .. out
end

-- todo: generate dynamically (eg. "more qualities" mods)
local qualityLookup = {
  ["normal"] = 0,
  ["uncommon"] = 1,
  ["rare"] = 2,
  ["epic"] = 3,
  ["legendary"] = 4
}

local iQualityLookup = {}
for i,j in pairs(qualityLookup) do iQualityLookup[j] = i end

-- debug
local function log(text)
  local players = game.players
  for x=1, #players do
    game.players[x].print(text)
  end
end


--------------------------------
-- representation definitions --
--------------------------------

local reprConfig = {}


--- representation: sh4dow
--- 
--- syntax: (r"..." means "matching this regex")
--- signal = [<category-prefix>]name[<quality-suffix>][<channel-suffix>]
--- category-prefix = <category-shorthand>.
--- quality-suffix = +(<+>|<quality-rank>|<quality-name>|"<quality-name>")
--- quality-rank = r"\d+" -- preferred over quality-name if ambiguous
--- quality-name = r"[a-zA-Z0-9-_]+"
--- + = [<+>]+
--- channel-suffix = #[r|R][g|G]
--- 
--- // preliminary
--- constant-combinator = <category> [--- <constant-combinator>]
--- category = [\[<categoryName>\]] entries
--- entries = [signal <count>][,<entries>]
--- 
--- decider-combinator = [<conditions>] : [<outputs>]
--- conditions = <signal> <operator> <signal_or_constant> [(& | \|) <conditions>]
--- signal_or_constant = <signal> | <count>
--- outputs = <signal> [= <count>] [, <outputs>]
--- 
--- arithmetic-combinator = <signal> <operator> <signal_or_constant> : <signal>
--- 
local sh4dowCfg = {}
reprConfig.sh4dow = sh4dowCfg
sh4dowCfg.quality = {[0]="", [1]="+", [2]="++", [3]="+++", [4]="++++", [5]="+++++"}
sh4dowCfg.categories = {
  ["virtual"] = "v.",
  ["entity"] = "e.",
  ["item"] = "",
  ["recipe"] = "r."
}
sh4dowCfg.iCategories = {}
for i,j in pairs(sh4dowCfg.categories) do sh4dowCfg.iCategories[j]=i end

---@param signal table?
local function signalFormat_sh4dow(signal) -- maybe change to (cat, name, quality)??
  if not signal then return "" end
  local ret = ""
  if signal.type then
    ret = ret .. (reprConfig.sh4dow.categories[signal.type] or "?")
  end
  ret = ret .. signal.name
  if signal.quality then
    ret = ret .. (reprConfig.sh4dow.quality[qualityLookup[signal.quality]] or "+?")
  end
  return ret
end

---@param netw table?
local function signalNetworkFormatter_sh4dow(netw)
  if not netw then return "" end
  return "#" .. (netw.green and "g" or "") .. (netw.red and "r" or "")
end

local function parseSignal(sig)
  -- "v.signal-each++#g"
  if not sig then return nil end
  local signal = {}
  local ftype, namepos = sig:match("^%s*(%w%.)()")
  signal.type = reprConfig.sh4dow.iCategories[ftype]
  signal.name = sig:sub(namepos or 1):match("^%s*([%w%-_]+)")
  local qual = #(sig:match("%++") or "") -- todo: exclusively consider directly after name??
  signal.quality = iQualityLookup[qual]
  return signal
end

local function parseSignalAndNetwork(str)
  local sig = parseSignal(str:match("^[^#]*"))
  local net = nil
  local nets = str:match("#[rRgG]*")
  if nets then
    net = {}
    net.green = nets:match("[gG]") and true or false
    net.red = nets:match("[rR]") and true or false
  end
  return sig, net
end

--- compact representation
--- TODO: add postprocess to add line breaks where helpful
--- ---@param type string
local function formatter_sh4dow(tbl, type)
  local ret = ""
  if type == "constant-combinator" then
    for i, group in ipairs(tbl) do
      -- logistic groups
      if group.group then
        ret = ret .. "[" .. group.group .. "]\n"
      end
      local ind = 1
      for i, signal in ipairs(group.filters or {}) do
        while signal.index > ind do
          ret = ret .. ","
          ind = ind + 1
        end
        ret = ret .. signalFormat_sh4dow(signal)
        ret = ret .. signal.count .. ","
        ind = ind + 1
      end
      ret = ret .. "\n---\n"
    end
    ret = ret:sub(1,-6)  -- remove trailing "---"
  elseif type == "decider-combinator" then
    -- probably first determine logical structure before actually formatting for fully featured version
    -- conditions
    for i, cond in ipairs(tbl.conditions) do
      if i>1 then
        ret = ret .. ((cond.compare_type=="and") and "& " or "| ")
      end
      ret = ret .. signalFormat_sh4dow(cond.first_signal) .. signalNetworkFormatter_sh4dow(cond.first_signal_networks) .. " "
      ret = ret .. (cond.comparator or "<") .. " " -- todo: replace "≠" with "!=" (and back)
      -- either second_signal or constant is usually set
      ret = ret .. signalFormat_sh4dow(cond.second_signal) .. signalNetworkFormatter_sh4dow(cond.second_signal_networks)
      ret = ret .. (cond.constant or (not cond.second_signal) and "0" or "") .. " "
    end
    ret = ret .. "-> "
    -- outputs
    for i, out in ipairs(tbl.outputs or {}) do
      ret = ret .. signalFormat_sh4dow(out.signal) .. signalNetworkFormatter_sh4dow(out.networks)
      if out.copy_count_from_input == false then
        ret = ret .. " = ".. (out.constant or 1)
      end
      ret = ret .. ", "
    end
    if ret:sub(-2,-2) == "," then -- don't break the "->"
      ret = ret:sub(1,-3) -- remove trailing ", "
    end
  elseif type == "arithmetic-combinator" then
    ret = ret .. signalFormat_sh4dow(tbl.first_signal) .. signalNetworkFormatter_sh4dow(tbl.first_signal_networks) .. " "
    ret = ret .. tbl.operation .. " "
    if tbl.second_constant then
      ret = ret .. tbl.second_constant .. " "
    else
      ret = ret .. signalFormat_sh4dow(tbl.second_signal) .. signalNetworkFormatter_sh4dow(tbl.second_signal_networks) .. " "
    end
    ret = ret .. ": "
    ret = ret .. signalFormat_sh4dow(tbl.output_signal)
  elseif type == "selector-combinator" then
    -- todo
  end
  return ret
end

local function parser_sh4dow(str, type)
  if type == "constant-combinator" then
    local root = {}
    local ind = 1
    for group in (str.."---"):gmatch("(.-)(\n?%-%-%-\n?)") do
      local grp = {}
      grp.index = ind
      ind = ind + 1
      if group:match("%[(.-)%]") then
        grp.group = group:match("%[(.-)%]")
      end
      local fil = {}
      local ind2 = 1
      for signal in (group..","):gmatch("([^,]-),") do
        local sig = parseSignal(signal)
        --local sig = {}
        --sig.name = signal:match("([%w%-_]+)")
        if sig and sig.name then
          --local qual = #(signal:match("[%w%-_]+(%+*)") or "")
          sig.comparator = "=" -- always "=" for constant combinator
          sig.count = signal:match("^%s*%w%.?[%w%-_]*%+*%s*(%-?%d+)") or 0
          sig.index = ind2
          --if signal:match("(%w+%.)") then
          --  sig.type = reprConfig.sh4dow.iCategories[signal:match("(%w+%.)")]
          --end
          table.insert(fil, sig)
        end
        ind2 = ind2 + 1
      end
      grp.filters = fil
      table.insert(root, grp)
    end
    return root
  elseif type == "decider-combinator" then
    local root = {}
    local conditions = str:match("^(.*)%->")
    local outputs = str:match("%->(.*)$")
    local condts = {}
    local ind = 1
    for n, cond in conditions:gmatch("()([^|&]+)") do
      local condt = {}
      local cmpt = conditions:sub(n,n)
      if ind>1 and cmpt == "&" then -- test this!
        condt.compare_type = "and"
      end
      ind = ind + 1
      local first = cond:match("^([^<>=≠≤≥]+)")
      local second = cond:match("([^<>=≠≤≥]+)$")
      local op = cond:match("([<>=≠≤≥]+)")
      condt.first_signal = parseSignal(first:match("^([^#]*)"))
      local channels = first:match("#[rg]+")
      if channels then
        condt.first_signal_networks = {}
        condt.first_signal_networks.green = channels:match("[gG]") and true or false -- string vs nil to true vs false
        condt.first_signal_networks.red = channels:match("[rR]") and true or false
      end
      condt.comparator = op -- todo: convert eg. >= to ≥ for ease of use
      if second:match("(%a)+") then -- has second signal
        condt.second_signal = parseSignal(second:match("^([^#]*)"))
        local channels = second:match("#[rg]+")
        if channels then
          condt.second_signal_networks = {}
          condt.second_signal_networks.green = channels:match("[gG]") and true or false -- string vs nil to true vs false
          condt.second_signal_networks.red = channels:match("[rR]") and true or false
        end
      else
        condt.constant = tonumber(second:match("(%-?%d+)"))
      end
      table.insert(condts,condt)
    end
    root.conditions = condts
    -- outputs
    local outs = {}
    for out in outputs:gmatch("[^,]+") do
      local outt = {}
      outt.signal = parseSignal(out:match("(%w%.?[%w%-_]*%+*)"))
      local channels = out:match("#[rg]+")
      if channels then
        outt.networks = {}
        outt.networks.green = channels:match("[gG]") and true or false
        outt.networks.red = channels:match("[rR]") and true or false
      end
      if out:match("(=)") then
        outt.copy_count_from_input = false
        outt.constant = tonumber(out:match("=%s*(%-?%d+)") or 1)
      end
      table.insert(outs, outt)
    end
    root.outputs = outs
    return root
  elseif type == "arithmetic-combinator" then
    -- todo
    local i, out = str:match("^([^:]*):([^:]*)$")
    local i1, op, i2 = i:match("([^ ]*) +([^ ]*) +([^ ]*)") -- space separation necessary since "-" is both part of signal names and an operator
    if i1 == nil then
      op, i2 = i:match("^ *([^ ]*) *([^ ]*) *$")
      if op == nil then
        op = i:match("^ *([^ ]*) *$")
      end
    end
    log("i1 "..i1)
    log("op "..op)
    log("i2 "..i2)
    log("out "..out)
    local root = {}
    root.first_signal, root.first_signal_networks = parseSignalAndNetwork(i1)
    root.op = op
    if tonumber(i2) then
      root.second_constant = tonumber(i2)
    else
      root.second_signal, root.second_signal_networks = parseSignalAndNetwork(i2)
    end
    root.output_signal = parseSignal(out)
    return root
  elseif type == "selector-combinator" then
    -- todo
  end
end

-- choose how to format the data
---@param player LuaPlayer
local function get_formatter(player)
  local choice = settings.get_player_settings(player.index)["cc-representation-type"].value
  if choice == "lua" then
    return function(tbl,_) return serpent.block(tbl, {custom=format_combinator_table, sortkeys=sort_combinator_table}) end
  elseif choice == "sh4dow" then
    return formatter_sh4dow
  elseif choice == "basic" or choice == "..." then
    return function() return "formatter not implemented" end
  else
    error("unknown representation")
  end

end

local function get_parser(player)
  local choice = settings.get_player_settings(player.index)["cc-representation-type"].value
  if choice == "lua" then
    return function(text, type)
      local func = loadstring("return " .. text)
      if not func then return end
      local cb_table = func()
    end
  elseif choice == "sh4dow" then
    return parser_sh4dow
  elseif choice == "basic" or choice == "..." then
    return function() return "formatter not implemented" end
  else
    error("unknown representation")
  end
end

---get the code describing an existing combinator
---@param combinator LuaEntity?
---@return string?
local function get_combinator_cb_code(combinator, formatter)
  if not formatter then
    formatter = function(tbl,_) serpent.block(tbl, {custom=format_combinator_table, sortkeys=sort_combinator_table}) end
  end
  if combinator and combinator.valid then
    -- create a temporary script inventory
    inv = game.create_inventory(1)
    -- create a blueprint containing [at least] the combinator
    inv.insert("blueprint")
    inv[1].create_blueprint {
      surface = combinator.surface,
      force = combinator.force,
      area = { combinator.position, combinator.position },
    }
    -- convert the blueprint to a json string
    local bp_json = helpers.decode_string(string.sub(inv[1].export_stack(), 2))
    -- clean up the temporary blueprint and script inventory
    inv.destroy()
    if bp_json then
      local bp_table = helpers.json_to_table(bp_json)
      if bp_table and bp_table.blueprint and bp_table.blueprint.entities then
        -- we aimed for one entity but may have caught multiple overlapping entities
        for i, entity in pairs(bp_table.blueprint.entities) do
          -- should probably throw error if multiple combinators in selection box
          if entity.name:match "%-combinator$" then
            -- hopefully just one combinator, though
            local cb_table = bp_table.blueprint.entities[1].control_behavior
            -- remove redundant/unnecessary outer layers from table
            if cb_table.sections then cb_table = cb_table.sections.sections end
            if cb_table.arithmetic_conditions then cb_table = cb_table.arithmetic_conditions end
            if cb_table.decider_conditions then cb_table = cb_table.decider_conditions end
            -- use the custom sort and format functions above to serialize the table to a string
            return formatter(cb_table, entity.name)--serpent.block(cb_table, { custom = format_combinator_table, sortkeys = sort_combinator_table })
          end
        end
      end
    end
  end
end

---when opening a combinator, create and populate the mod gui
---@param event EventData.on_gui_opened
local function on_gui_opened(event)
  local entity = event.entity
  if not entity or not entity.valid or not entity.type:match "%-combinator$" then return end
  local player = game.get_player(event.player_index)
  if not player then return end

  -- destroy the frame if it still exists from previously
  local relative_frame = player.gui.relative["combinator-codify"]
  if relative_frame then relative_frame.destroy() end

  -- anchor the frame below the constant combinator gui
  ---@type GuiAnchor]
  local anchor = { gui = defines.relative_gui_type[entity.type:gsub("-", "_") .. "_gui"], position = defines
  .relative_gui_position.right }
  local frame = (player.gui.relative.add { type = "frame", anchor = anchor, name = "combinator-codify", caption = "Combinator Code", direction = "vertical" })
  frame.style.width = 600
  local textbox = frame.add { type = "text-box", name = "combinator-codify-textbox", text = get_combinator_cb_code(entity, get_formatter(player)) }
  textbox.style.width = 580
  textbox.style.vertically_squashable = true
  textbox.style.font = "combinator-codify"
  textbox.style.rich_text_setting = defines.rich_text_setting.enabled
  local button_flow = (frame.add { type = "flow", name = "combinator-codify-button-flow", direction = "horizontal" })
  button_flow.add { type = "button", name = "combinator-codify-apply-button", caption = "Apply" }
  button_flow.add { type = "button", name = "combinator-codify-refresh-button", caption = "Refresh" }
  button_flow.add { type = "button", name = "combinator-codify-richtext-button", caption = "Rich Text" }
end

local next_rich_text_setting = {
  [defines.rich_text_setting.disabled] = defines.rich_text_setting.enabled,
  [defines.rich_text_setting.enabled] = defines.rich_text_setting.highlight,
  [defines.rich_text_setting.highlight] = defines.rich_text_setting.disabled,
}

---use the text in a player's mod gui to set the signals in their open combinator
---@param event EventData.on_gui_click | EventData.on_gui_confirmed
local function on_gui_apply(event)
  local element = event.element
  if
      element.valid and element.parent and (element.parent.name == "combinator-codify" or element.parent.name == "combinator-codify-button-flow") and
      (
        (event.name == defines.events.on_gui_click and element.type == "button") or
        (event.name == defines.events.on_gui_confirmed and element.type == "text-box")
      )
  then
    local player = game.get_player(event.player_index)
    if not player then return end
    local entity = player.opened
    if not entity or not entity.valid or not entity.type:match "%-combinator$" then return end
    local textbox = player.gui.relative["combinator-codify"]["combinator-codify-textbox"]
    if element.name == "combinator-codify-refresh-button" then
      local tmp = get_formatter(player)
---@diagnostic disable-next-line: assign-type-mismatch, param-type-mismatch
      textbox.text = get_combinator_cb_code(player.opened, get_formatter(player)) or ""
    elseif element.name == "combinator-codify-richtext-button" then
      textbox.style.rich_text_setting = next_rich_text_setting[textbox.style.rich_text_setting]
    else
      local combinator = game.get_player(event.player_index).opened --[[@as LuaEntity]]
      if combinator and combinator.valid then
        local text = textbox.text
        local parser = get_parser(player)
---@diagnostic disable-next-line: deprecated
        local cb_table = parser(text, combinator.type)
        if cb_table then
          -- restore redundant/unnecessary outer layer to table
          if combinator.type == "constant-combinator" then
            cb_table = { sections = { sections = cb_table } }
          elseif combinator.type == "arithmetic-combinator" then
            cb_table = { arithmetic_conditions = cb_table }
          elseif combinator.type == "decider-combinator" then
            cb_table = { decider_conditions = cb_table }
          end
          local full_table = {
            blueprint = {
              entities = {
                {
                  entity_number = 1,
                  name = combinator.name,
                  position = combinator.position,
                  direction = combinator.direction,
                  control_behavior = cb_table
                }
              }
            }
          }
          local bp_json = helpers.table_to_json(full_table)
          inv = game.create_inventory(1)
          inv.insert("blueprint")
          inv[1].import_stack(bp_json)
          inv[1].build_blueprint {
            surface = combinator.surface,
            force = combinator.force,
            position = combinator.position,
            raise_built = false,
          }
          inv.destroy()
        end
      end
    end
  end
end

script.on_event(defines.events.on_gui_opened, on_gui_opened)
script.on_event(defines.events.on_gui_click, on_gui_apply)
script.on_event(defines.events.on_gui_confirmed, on_gui_apply)
