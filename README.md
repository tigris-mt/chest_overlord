# API
## Commands
* `{type = "move", from = <slot>, to = <slot>}`
* `{type = "inv"}`
* `{type = "slot", index = <slot>}`
## Item Format
* `{name = "mod:item", count = 1, meta = {a = 1, b = 2}, wear = 0}`
## Events
* `{type = "event", event = "put", pipe = false, player = "singleplayer", index = 1, item = <item>}`
* `{type = "event", event = "move", player = "singleplayer", from = 4, to = 6}`
## Responses
* `{type = "inv", list = {<item>, {count = 0}, <item>, ...}}`
* `{type = "slot", index = 4, item = <item>}`
* `{type = "success"}`
* `{type = "error", error = "slot"}`
