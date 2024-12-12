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

---get the code describing an existing combinator
---@param combinator LuaEntity?
---@return string?
local function get_combinator_cb_code(combinator)
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
          if entity.name:match "%-combinator$" then
            -- hopefully just one combinator, though
            local cb_table = bp_table.blueprint.entities[1].control_behavior
            -- remove redundant/unnecessary outer layers from table
            if cb_table.sections then cb_table = cb_table.sections.sections end
            if cb_table.arithmetic_conditions then cb_table = cb_table.arithmetic_conditions end
            if cb_table.decider_conditions then cb_table = cb_table.decider_conditions end
            -- use the custom sort and format functions above to serialize the table to a string
            return serpent.block(cb_table, { custom = format_combinator_table, sortkeys = sort_combinator_table })
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
  local textbox = frame.add { type = "text-box", name = "combinator-codify-textbox", text = get_combinator_cb_code(entity) }
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
    local textbox = player.gui.relative["combinator-codify"]["combinator-codify-textbox"]
    if element.name == "combinator-codify-refresh-button" then
      textbox.text = get_combinator_cb_code(player.opened)
    elseif element.name == "combinator-codify-richtext-button" then
      textbox.style.rich_text_setting = next_rich_text_setting[textbox.style.rich_text_setting]
    else
      local combinator = game.get_player(event.player_index).opened --[[@as LuaEntity]]
      if combinator and combinator.valid then
        local text = textbox.text
        local func = loadstring("return " .. text)
        if func then
          local cb_table = func()
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
