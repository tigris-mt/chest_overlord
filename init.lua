local m = {}
chest_overlord = m

-- Serialize stack into easy format.
function m.describe_stack(stack)
    return {
        name = stack:get_name(),
        count = stack:get_count(),
        meta = stack:get_meta():to_table().fields,
        wear = stack:get_wear(),
    }
end

function m.register(name, d)
    -- Check protection.
    local function can(pos, name)
        return not (d.protected and minetest.is_protected(pos, name))
    end

    -- Build formspec according to size.
    local function fs(meta)
        local mx = math.max(8, d.size_x)
        meta:set_string("formspec",
            "size[" .. mx .. "," .. (6 + d.size_y) .. "]"..
            "list[current_name;main;0,0;" .. d.size_x .. "," .. d.size_y .. ";]"..
            "list[current_player;main;0," .. 1 + d.size_y .. ";8,4;]"..
            "field[0.5," .. (6 + d.size_y) .. ";" .. (mx - 0.5) .. ",0;channel;Digiline channel:;" .. minetest.formspec_escape(meta:get_string("channel")) .. "]" ..
            "listring[context;main]listring[current_player;main]")
    end

    local function reply(pos, msg)
        digiline:receptor_send(pos, digiline.rules.default, minetest.get_meta(pos):get_string("channel"), msg)
    end

    local def = {
        groups = {snappy = 2, choppy = 2, oddly_breakable_by_hand = 2, tubedevice = 1, tubedevice_receiver = 1},
        on_construct = function(pos)
            local meta = minetest.get_meta(pos)
            fs(meta)
            local inv = meta:get_inventory()
            inv:set_size("main", d.size_x * d.size_y)
        end,
        can_dig = function(pos, player)
            local meta = minetest.get_meta(pos);
            local inv = meta:get_inventory()
            return inv:is_empty("main")
        end,
        on_receive_fields = function(pos, _, fields, sender)
            local meta = minetest.get_meta(pos)
            if can(pos, sender) then
                if fields.channel then
                    meta:set_string("channel", fields.channel)
                    fs(meta)
                end
            end
        end,
        digiline = {
            receptor = {},
            effector = {
                action = function(pos, node, channel, msg)
                    local meta = minetest.get_meta(pos)
                    if meta:get_string("channel") ~= channel then
                        return
                    end
                    if type(msg) ~= "table" or not msg.type then
                        return
                    end

                    local main = meta:get_inventory():get_list("main")

                    if msg.type == "inv" then
                        local ret = {}
                        for idx,stack in ipairs(main) do
                            ret[idx] = m.describe_stack(stack)
                        end
                        reply(pos, {list = ret, type = "inv"})
                    elseif msg.type == "slot" then
                        if main[msg.index] then
                            reply(pos, {type = "slot", index = msg.index, item = m.describe_stack(main[msg.index])})
                        else
                            reply(pos, {type = "error", error = "slot"})
                        end
                    elseif msg.type == "move" then
                        if main[msg.from] and main[msg.to] then
                            -- Swap slots.
                            local tmp = main[msg.to]
                            main[msg.to] = main[msg.from]
                            main[msg.from] = tmp
                            -- And write list back.
                            meta:get_inventory():set_list("main", main)
                            reply(pos, {type = "moveok"})
                        else
                            reply(pos, {type = "error", error = "slot"})
                        end
                    elseif msg.type == "label" then
                        meta:set_string("infotext", tostring(msg.text))
                    elseif msg.type == "sbp_memory_set" and minetest.get_modpath("sbp_memory") then
                        if main[msg.index] and minetest.get_item_group(main[msg.index]:get_name(), "sbp_memory") > 0 then
                            local ok, err = minetest.registered_items[main[msg.index]:get_name()].sbp_set(main[msg.index]:get_meta(), msg.data)
                            if ok then
                                meta:get_inventory():set_list("main", main)
                                reply(pos, {type = "memset"})
                            else
                                reply(pos, {type = "error", error = "memset", mem_error = err})
                            end
                        else
                            reply(pos, {type = "error", error = "slot"})
                        end
                    elseif msg.type == "sbp_memory_get" and minetest.get_modpath("sbp_memory") then
                        if main[msg.index] and minetest.get_item_group(main[msg.index]:get_name(), "sbp_memory") > 0 then
                            reply(pos, {type = "memget", data = minetest.deserialize(main[msg.index]:get_meta():get_string("data"))})
                        else
                            reply(pos, {type = "error", error = "slot"})
                        end
                    end
                end,
            },
        },

        allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
            return can(pos, player:get_player_name()) and count or 0
        end,

        allow_metadata_inventory_put = function(pos, listname, index, stack, player)
            return can(pos, player:get_player_name()) and stack:get_count() or 0
        end,

        allow_metadata_inventory_take = function(pos, listname, index, stack, player)
            return can(pos, player:get_player_name()) and stack:get_count() or 0
        end,

        on_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
            reply(pos, {
                type = "event",
                event = "move",
                player = player:get_player_name(),
                from = from_index,
                to = to_index,
            })
        end,

        on_metadata_inventory_put = function(pos, listname, index, stack, player)
            reply(pos, {
                type = "event",
                event = "put",
                pipe = false,
                player = player:get_player_name(),
                index = index,
                item = m.describe_stack(stack),
            })
        end,

        on_metadata_inventory_take = function(pos, listname, index, stack, player)
            reply(pos, {
                type = "event",
                event = "take",
                pipe = false,
                player = player:get_player_name(),
                index = index,
                item = m.describe_stack(stack),
            })
        end,

        tube = {
            insert_object = function(pos, node, stack, direction)
                local meta = minetest.get_meta(pos)
                local inv = meta:get_inventory()
                local index = nil
                for idx=1,inv:get_size("main") do
                    local i = inv:get_stack("main", idx)
                    if i:get_name() == stack:get_name() and i:get_definition() then
                        if i:get_count() + stack:get_count() <= i:get_definition().stack_max then
                            index = idx
                            break
                        end
                    elseif i:get_count() == 0 then
                        index = idx
                        break
                    end
                end
                reply(pos, {
                    type = "event",
                    event = "put",
                    pipe = true,
                    index = index,
                    item = m.describe_stack(stack),
                })
                return inv:add_item("main",stack)
            end,
            can_insert = function(pos, node, stack, direction)
                    local meta = minetest.get_meta(pos)
                    local inv = meta:get_inventory()
                    return inv:room_for_item("main", stack)
            end,
            input_inventory = "main",
            connect_sides = {left=1, right=1, front=1, back=1, top=1, bottom=1},
        },

        after_place_node = pipeworks.after_place,
        after_dig_node = pipeworks.after_dig,
    }
    for k,v in pairs(d) do
        def[k] = v
    end

    minetest.register_node(name, def)
end

local d = {
    drawtype = "normal",
    size_x = 14,
    size_y = 4,
}

d.description = "Public Overlord Chest"
d.tiles = {"chest_overlord_public.png"}
m.register("chest_overlord:public", d)

d.description = "Protected Overlord Chest"
d.protected = true
d.tiles = {"chest_overlord_protected.png"}
m.register("chest_overlord:protected", d)

minetest.register_craft{
    output = "chest_overlord:public",
    recipe = {
        {"default:mese_crystal", "digilines:wire_std_00000000", "default:mese_crystal"},
        {"default:mese_crystal", "", "default:mese_crystal"},
        {"default:mese_crystal", "default:mese_crystal", "default:mese_crystal"},
    },
}

minetest.register_craft{
    output = "chest_overlord:protected",
    recipe = {
        {"default:mese_crystal", "digilines:wire_std_00000000", "default:mese_crystal"},
        {"default:mese_crystal", "default:copper_ingot", "default:mese_crystal"},
        {"default:mese_crystal", "default:mese_crystal", "default:mese_crystal"},
    },
}

minetest.register_craft{
    output = "chest_overlord:protected",
    type = "shapeless",
    recipe = {"chest_overlord:public", "default:copper_ingot"},
}
