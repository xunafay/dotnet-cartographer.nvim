---@class Directory
---@field name string The name of the directory
---@field path string The relative normalized path to the directory
---@field children Node[] The child nodes (files and subdirectories) of this directory
---@field kind 'directory'

---@alias Node Project|Directory

---@class Project
---@field name string The project name
---@field path string The relative normalized path to the project file
---@field kind 'project'

local Project = {}
Project.__index = Project

--- Creates a new Project instance
---@param name string The project name
---@param path string The relative normalized path to the project file
---@return Project
function Project.new(name, path)
	local self = setmetatable({}, Project)
	self.name = name
	self.path = path
	return self
end

---@class Solution
---@field path string The absolute path to the solution file
---@field header SolutionHeader The parsed solution header information
---@field tree Node[]
local Solution = {}
Solution.__index = Solution

--- Creates a new Solution instance
---@param path string The relative path to the solution file
---@param header SolutionHeader|nil The parsed solution header information
---@return Solution
function Solution.new(path, header)
	local self = setmetatable({}, Solution)
	self.path = path
	self.header = header
		or {
			visual_studio_version = nil,
			file_version = nil,
			minimum_visual_studio_version = nil,
		}
	self.tree = {}
	return self
end

--- Adds a project to the solution
---@param project Project The project to add
---@param directory string|nil The relative path to the directory within the solution where the project should be added (e.g., "src/utils"). If nil, the project is added at the root level of the solution.
function Solution:add_project(project, directory)
	if directory then
		local parts = {}
		for part in string.gmatch(directory, "([^/]+)") do
			table.insert(parts, part)
		end

		local current_node = self.tree
		for _, part in ipairs(parts) do
			local found = false
			for _, node in ipairs(current_node) do
				if node.name == part and node.kind == "directory" then
					current_node = node.children
					found = true
					break
				end
			end

			if not found then
				local new_dir = {
					name = part,
					path = nil,
					kind = "directory",
					children = {},
				}
				table.insert(current_node, new_dir)
				current_node = new_dir.children
			end
		end

		table.insert(current_node, {
			name = project.name,
			kind = "project",
			path = project.path,
		})
	else
		table.insert(self.tree, {
			name = project.name,
			kind = "project",
			path = project.path,
		})
	end
end

local M = {}
M.Solution = Solution

return M
