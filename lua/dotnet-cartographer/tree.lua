-- copy of snacks.nvim.explorer.tree with adjustments for supporting virtual nodes

---@class snacks.picker.explorer.Node
---@field path string          -- position in the virtual tree
---@field disk_path? string    -- real filesystem path (nil for virtual nodes)
---@field name string
---@field text? string
---@field hidden? boolean
---@field status? string merged git status
---@field dir_status? string git status of the directory
---@field ignored? boolean
---@field type "file"|"directory"|"link"|"fifo"|"socket"|"char"|"block"|"unknown"|"solution"|"project"
---@field dir? boolean
---@field open? boolean wether the node should be expanded in the tree (only for type directory|project|solution|virtual)
---@field expanded? boolean wether the node is expanded (only for directories)
---@field parent? snacks.picker.explorer.Node
---@field last? boolean child of the parent
---@field utime? number
---@field children table<string, snacks.picker.explorer.Node>
---@field severity? number

---@class snacks.picker.explorer.Filter
---@field hidden? boolean show hidden files
---@field ignored? boolean show ignored files
---@field exclude? string[] globs to exclude
---@field include? string[] globs to exclude

---@alias snacks.picker.explorer.Snapshot {fields: string[], state:table<snacks.picker.explorer.Node, any[]>}

local uv = vim.uv or vim.loop

local function norm(path)
	return vim.fs.normalize(path):gsub("/$", ""):gsub("^$", "/")
end

local function assert_dir(path)
	assert(vim.fn.isdirectory(path) == 1, "Not a directory: " .. path)
end

-- local function assert_file(path)
--   assert(vim.fn.filereadable(path) == 1, "Not a file: " .. path)
-- end

---@class snacks.picker.explorer.Tree
---@field root snacks.picker.explorer.Node
---@field nodes table<string, snacks.picker.explorer.Node>
local Tree = {}
Tree.__index = Tree

function Tree.new(opts)
	local self = setmetatable({}, Tree)

	self.opts = vim.tbl_extend("force", {
		project_markers = { ".git", ".project", "package.json" },
	}, opts or {})

	self.root = { name = "", children = {}, dir = true, type = "directory", path = "" }
	self.nodes = {}

	return self
end

function Tree:is_project(path)
	for _, marker in ipairs(self.opts.project_markers) do
		if vim.loop.fs_stat(path .. "/" .. marker) then
			return true
		end
	end
	return false
end

--- Add a pure virtual directory
---@param parent_path? string path of the parent node (nil or '' for root)
---@param name string display name
---@return snacks.picker.explorer.Node
function Tree:add_virtual(parent_path, name)
	local parent
	if parent_path == nil or parent_path == "" then
		parent = self.root
	else
		parent = self.nodes[parent_path]
		assert(parent, "Parent node not found: " .. parent_path)
	end

	local path = parent == self.root and name or (parent.path .. "/" .. name)

	local node = {
		name = name,
		text = name,
		path = path,
		parent = parent,
		children = {},
		type = "virtual",
		dir = true,
		open = true,
	}

	parent.children[name] = node
	self.nodes[path] = node

	return node
end

--- Attach a real filesystem directory as a project node
---@param parent_path? string path of the parent node (nil or '' for root)
---@param disk_path string absolute filesystem path to the real directory
---@param name? string display name override (defaults to the directory's basename)
---@return snacks.picker.explorer.Node
function Tree:add_project(parent_path, disk_path, name)
	disk_path = vim.fs.normalize(disk_path)
	assert(vim.fn.isdirectory(disk_path) == 1, "Not a directory: " .. disk_path)

	local parent
	if parent_path == nil or parent_path == "" then
		parent = self.root
	else
		parent = self.nodes[parent_path]
		assert(parent, "Parent node not found: " .. parent_path)
	end

	name = name or vim.fs.basename(disk_path)
	local virtual_path = parent == self.root and name or (parent.path .. "/" .. name)

	local node = {
		name = name,
		text = name,
		path = virtual_path,
		disk_path = disk_path,
		parent = parent,
		children = {},
		type = "project",
		dir = true,
		open = false,
	}

	parent.children[name] = node
	self.nodes[virtual_path] = node

	return node
end

---@param path string
---@return snacks.picker.explorer.Node?
function Tree:node(path)
	path = norm(path)
	return self.nodes[norm(path)]
end

---@param path string
function Tree:find(path)
	path = norm(path)
	if self.nodes[path] then
		return self.nodes[path]
	end

	local node = self.root
	local parts = vim.split(path, "/", { plain = true })
	local is_dir = vim.fn.isdirectory(path) == 1
	for p, part in ipairs(parts) do
		node = self:child(node, part, (is_dir or p < #parts) and "directory" or "file")
	end
	return node
end

---@param node snacks.picker.explorer.Node
---@param name string
---@param type string
function Tree:child(node, name, type)
	if not node.children[name] then
		local path = node.path .. "/" .. name
		path = node == self.root and name or path

		node.children[name] = {
			name = name,
			path = path,
			parent = node,
			children = {},
			type = type,
			dir = type == "directory"
				or type == "virtual"
				or type == "project"
				or (type == "link" and vim.fn.isdirectory(path) == 1),
			hidden = name:sub(1, 1) == ".",
		}

		self.nodes[path] = node.children[name]
	end

	return node.children[name]
end

---@param path string
function Tree:open(path)
	local dir = self:dir(path)
	local node = self:find(dir)
	while node do
		node.open = true
		node = node.parent
	end
end

---@param path string
function Tree:toggle(path)
	local dir = self:dir(path)
	local node = self:find(dir)
	if node.open then
		self:close(dir)
	else
		self:open(dir)
	end
end

---@param path string
function Tree:show(path)
	self:open(vim.fs.dirname(path))
end

---@param path string
function Tree:close(path)
	local dir = self:dir(path)
	local node = self:find(dir)
	node.open = false
	node.expanded = false
end

---@param node snacks.picker.explorer.Node
function Tree:expand(node)
	if node.expanded then
		return
	end

	assert(node.dir, "Can only expand directories")

	-- No disk_path means purely virtual node — children are managed manually
	if not node.disk_path then
		node.expanded = true
		return
	end

	local found = {}
	local fs = uv.fs_scandir(node.disk_path)

	while fs do
		local name, t = uv.fs_scandir_next(fs)
		if not name then
			break
		end

		t = t or Snacks.util.path_type(node.disk_path .. "/" .. name)
		found[name] = true

		local child = self:child(node, name, t)
		child.type = t == "directory" and "directory" or t
		child.dir = t == "directory"
			or t == "project"
			or (t == "link" and vim.fn.isdirectory(node.disk_path .. "/" .. name) == 1)
		child.disk_path = node.disk_path .. "/" .. name
	end

	for name in pairs(node.children) do
		local c = node.children[name]
		if c.disk_path and not found[name] then
			node.children[name] = nil
			self.nodes[c.path] = nil
		end
	end

	node.expanded = true
	node.utime = uv.hrtime()
end

---@param path string
function Tree:dir(path)
	return vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
end

---@param path string
function Tree:refresh(path)
	local dir = self:dir(path)
	require("snacks.explorer.git").refresh(dir)
	local root = self:node(dir)
	if not root then
		return
	end
	self:walk(root, function(node)
		node.expanded = nil
	end, { all = true })
end

---@param node snacks.picker.explorer.Node
---@param fn fun(node: snacks.picker.explorer.Node):boolean? return `false` to not process children, `true` to abort
---@param opts? {all?: boolean}
function Tree:walk(node, fn, opts)
	local abort = false ---@type boolean?
	abort = fn(node)
	if abort ~= nil then
		return abort
	end
	local children = vim.tbl_values(node.children) ---@type snacks.picker.explorer.Node[]
	table.sort(children, function(a, b)
		if a.dir ~= b.dir then
			return a.dir
		end
		return a.name < b.name
	end)
	for c, child in ipairs(children) do
		child.last = c == #children
		abort = false
		if child.dir and (child.open or (opts and opts.all)) then
			abort = self:walk(child, fn, opts)
		else
			abort = fn(child)
		end
		if abort then
			return true
		end
	end
	return false
end

---@param filter snacks.picker.explorer.Filter
function Tree:filter(filter)
	local exclude = filter.exclude and #filter.exclude > 0 and Snacks.picker.util.globber(filter.exclude)
	local include = filter.include and #filter.include > 0 and Snacks.picker.util.globber(filter.include)
	return function(node)
		-- takes precedence over all other filters
		if include and include(node.path) then
			return true
		end
		if node.hidden and not filter.hidden then
			return false
		end
		if node.ignored and not filter.ignored then
			return false
		end
		if exclude and exclude(node.path) then
			return false
		end
		return true
	end
end

---@param cwd string
---@param cb fun(node: snacks.picker.explorer.Node)
---@param opts? {expand?: boolean}|snacks.picker.explorer.Filter
function Tree:get(cwd, cb, opts)
	opts = opts or {}

	local node = self:node(cwd) or self:find(cwd)

	if node.disk_path then
		assert_dir(node.disk_path)
	elseif node.type ~= "virtual" then
		assert_dir(cwd)
	end

	node.open = true
	node.last = true

	local filter = self:filter(opts)

	self:walk(node, function(n)
		if n ~= node then
			if not filter(n) then
				return false
			end
		end
		if n.dir and n.open and not n.expanded and opts.expand ~= false then
			self:expand(n)
		end
		cb(n)
	end)
end

---@param cwd string
---@param opts? snacks.picker.explorer.Filter
function Tree:is_dirty(cwd, opts)
	opts = opts or {}
	if require("snacks.explorer.git").is_dirty(cwd) then
		return true
	end
	local dirty = false
	self:get(
		cwd,
		function(n)
			if n.dir and n.open and not n.expanded then
				dirty = true
			end
		end,
		{ hidden = opts.hidden, ignored = opts.ignored, exclude = opts.exclude, include = opts.include, expand = false }
	)
	return dirty
end

---@param cwd string
---@param path string
function Tree:in_cwd(cwd, path)
	local dir = vim.fs.dirname(path)
	return dir == cwd or dir:find(cwd .. "/", 1, true) == 1
end

---@param cwd string
---@param path string
function Tree:is_visible(cwd, path)
	assert_dir(cwd)
	if cwd == path then
		return true
	end
	local dir = vim.fs.dirname(path)
	if not self:in_cwd(cwd, path) then
		return false
	end
	local node = self:node(dir)
	while node do
		if node.path == cwd then
			return true
		elseif not node.open then
			return false
		end
		node = node.parent
	end
	return false
end

---@param cwd string
function Tree:close_all(cwd)
	self:walk(self:find(cwd), function(node)
		node.open = false
	end, { all = true })
end

---@param cwd string
---@param filter fun(node: snacks.picker.explorer.Node):boolean?
---@param opts? {up?: boolean, path?: string}
function Tree:next(cwd, filter, opts)
	opts = opts or {}
	local path = opts.path or cwd
	local root = self:node(cwd) or nil
	if not root then
		return
	end
	local first ---@type snacks.picker.explorer.Node?
	local last ---@type snacks.picker.explorer.Node?
	local prev ---@type snacks.picker.explorer.Node?
	local next ---@type snacks.picker.explorer.Node?
	local found = false
	self:walk(root, function(node)
		local want = not node.dir and filter(node) and not node.ignored
		if node.path == path then
			found = true
		end
		if want then
			first, last = first or node, node
			next = next or (found and node.path ~= path and node) or nil
			prev = not found and node or prev
		end
	end, { all = true })
	if opts.up then
		return prev or last
	end
	return next or first
end

---@param node snacks.picker.explorer.Node
---@param snapshot snacks.picker.explorer.Snapshot
function Tree:changed(node, snapshot)
	local old = snapshot.state
	local current = self:snapshot(node, snapshot.fields).state
	if vim.tbl_count(current) ~= vim.tbl_count(old) then
		return true
	end
	for n, data in pairs(current) do
		local prev = old[n]
		if not prev then
			return true
		end
		if not vim.deep_equal(prev, data) then
			return true
		end
	end
	return false
end

---@param node snacks.picker.explorer.Node
---@param fields string[]
function Tree:snapshot(node, fields)
	---@type snacks.picker.explorer.Snapshot
	local ret = {
		state = {},
		fields = fields,
	}
	Tree:walk(node, function(n)
		local data = {} ---@type any[]
		for f, field in ipairs(fields) do
			data[f] = n[field]
		end
		ret.state[n] = data
	end, { all = true })
	return ret
end

return Tree
