local M = {}
local Solution = require("dotnet-cartographer.parser.solution").Solution

--- @private
local function normalize(path)
	return vim.fn.fnamemodify(path, ":p")
end

--- @param slnx_path string The absolute path to the .slnx file
--- @return Solution|nil A Solution object if parsing was successful, or nil if the file could not be read
function M.parse_projects(slnx_path)
	local lines = vim.fn.readfile(slnx_path)
	if not lines then
		vim.notify("Failed to read .slnx file: " .. slnx_path, vim.log.levels.ERROR)
		return nil
	end

	local solution = Solution.new(slnx_path)
	local solution_dir = vim.fs.dirname(slnx_path)

	local folder_start_pattern = '<Folder%s+Name="([^"]+)"'
	local folder_end_pattern = "</Folder>"
	local project_pattern = '<Project%s+Path="([^"]+%.csproj)"'

	local current_folder = nil

	for _, line in ipairs(lines) do
		local folder_name = line:match(folder_start_pattern)
		if folder_name then
			current_folder = folder_name
		elseif line:match(folder_end_pattern) then
			current_folder = nil
		else
			local relative_path = line:match(project_pattern)
			if relative_path then
				local full_path

				if relative_path:match("^%a:[/\\]") or relative_path:sub(1, 1) == "/" then
					full_path = relative_path
				else
					full_path = solution_dir .. "/" .. relative_path
				end

				full_path = vim.fs.dirname(normalize(full_path))

				local name = vim.fs.basename(full_path)

				solution:add_project({
					name = name,
					path = full_path,
					kind = "project",
				}, current_folder)
			end
		end
	end

	return solution
end

return M
