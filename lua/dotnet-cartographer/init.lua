local Snacks = require("snacks")
local parser = require("dotnet-cartographer.parser")

local M = {
	state = {
		slnx_path = nil,
		root_path = nil,
		tree = nil, ---@type snacks.picker.explorer.Tree
	},
}

function M.config(opts)
	opts = opts or {}
	opts.tree = true
	opts.watch = true
	opts.matcher = { sort_empty = false, fuzzy = false }

	return opts
end

function M.pick_solution()
	Snacks.picker.files({
		title = "Select Solution",
		finder = "files",
		args = { "--glob", "*.slnx" },
		show_empty = false,
		auto_confirm = true,
		actions = {
			confirm = function(picker, item)
				picker:close()
				M.state.slnx_path = item.file
			end,
		},
	})
end

function M.finder(opts, ctx)
	if not M.state.tree then
		local Tree = require("dotnet-cartographer.tree")
		local tree = Tree.new()

		local solution = parser.parse_projects(M.state.slnx_path) ---@type Solution|nil

		if not solution then
			Snacks.notify("Failed to parse solution: " .. M.state.slnx_path, vim.log.levels.ERROR)
			return {}
		end

		local solution_name = vim.fn.fnamemodify(M.state.slnx_path, ":t:r")
		local root = tree:add_virtual("", solution_name)

		local function add_nodes(parent, nodes)
			for _, node in ipairs(nodes) do
				if node.kind == "directory" then
					local dir_node = tree:add_virtual(parent.path or parent.name, node.name)
					add_nodes(dir_node, node.children)
				elseif node.kind == "project" then
					tree:add_project(parent.path or parent.name, node.path, node.name)
				end
			end
		end

		add_nodes(root, solution.tree)

		M.state.tree = tree
		M.state.root_path = root.path
	end

	local items = {}
	M.state.tree:get(M.state.root_path, function(node)
		table.insert(items, node)
	end, { expand = true })

	return items
end

function M.format(item, picker)
	local ret = {}

	-- build tree prefix
	local node = item
	local indent = {} ---@type string[]
	while node and node.parent and node.parent.path ~= "" do
		local is_last = node.last
		local icon = ""
		if node ~= item then
			icon = is_last and "  " or "│ "
		else
			icon = is_last and "└╴" or "├╴"
		end

		table.insert(indent, 1, icon)
		node = node.parent
	end
	ret[#ret + 1] = { table.concat(indent), "SnacksPickerTree" }

	-- add icon and name
	if item.dir then
		local name = item.text or item.name or "INVALID NODE"
		if item.type == "directory" then
			local icon = item.open and "󰝰 " or "󰉋 "
			ret[#ret + 1] = { icon .. " " .. name, "SnacksPickerDirectory" }
		elseif item.type == "virtual" then
			local icon = item.open and "󰝰 " or "󰉋 "
			ret[#ret + 1] = { icon .. " " .. name, "SnacksPickerDirectory" }
		elseif item.type == "solution" then
			local icon, icon_hl = Snacks.util.icon("slnx", "extension")
			ret[#ret + 1] = { icon .. " " .. name, icon_hl }
		elseif item.type == "project" then
			local icon, icon_hl = Snacks.util.icon("csproj", "extension")
			ret[#ret + 1] = { icon .. " ", icon_hl }
			ret[#ret + 1] = { name, "SnacksPickerProject" }
		end
	else
		local file_name = vim.fs.basename(item.path)
		local icon, icon_hl = Snacks.util.icon(file_name, "file")
		table.insert(ret, { icon .. " ", icon_hl })
		table.insert(ret, { file_name, "SnacksPickerFile" })
	end

	return ret
end

function M.setup()
	Snacks.picker.sources.cartographer = {
		title = "Solution Explorer",
		tree = true,
		jump = {
			close = false,
		},
		auto_close = false,
		layout = {
			preset = "sidebar",
			preview = false,
			width = 35,
		},
		format = M.format,
		finder = M.finder,
		actions = {
			confirm = function(picker, item, action)
				if not item then
					return
				end

				if item.dir then
					item.open = not item.open
					if not item.open then
						item.expanded = false
					end
					picker:refresh()
				elseif item.disk_path then
					item.file = item.disk_path
					Snacks.picker.actions.jump(picker, item, action)
				end
			end,
		},
		keys = {
			win = {
				list = {
					["<cr>"] = "confirm",
					["o"] = "confirm",
					["<2-LeftMouse>"] = "confirm",
				},
			},
		},
	}
end

return M
