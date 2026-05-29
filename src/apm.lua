local version = "2.0.2"
local uv = require("luv")
--local apk = require("apk") -- apk-tool's lua bindings arent really helpful and are too much of a pain to compile
local json = require("dkjson")

local argparse = require("argparse")
local parser = argparse("apm", "apk (alpine package keeper) wrapper with QoL improvements")
parser:command_target("command")
parser:flag("-v --version"):action(function()
	print("apm v" .. version)
	os.exit(0)
end)
parser:flag("-v --verbose", "Show verbose/debug output"):args(0)
parser:flag("--auth-helper", "Specify the tool to use for priveledge escalation", (uv.getuid() == 0 and "none" or "polkit"))
	:args("1")
	:target("auth_tool")
	:choices({ "polkit", "sudo", "doas", "none" })
	:convert({
		polkit = "pkexec",
		sudo = "sudo",
		doas = "doas",
		none = ""
	})

local install = parser:command("install", "Install packages onto the system")
install:argument("packages"):args("+")
install:flag("-y --yes", "Assume yes on all prompts"):args(0)

local uninstall = parser:command("uninstall", "Remove packages from the system")
uninstall:argument("packages"):args("+")
uninstall:flag("-y --yes", "Assume yes on all prompts"):args(0)

local update = parser:command("update", "Update the system")
update:flag("-r --repos", "Update only the package repositories/index of the system"):args(0)

local args = parser:parse()

local colors = require("colors")
local log = {
	prefix = {
		verbose = colors.CYAN .. "VERBOSE" .. colors.WHITE .. ": ",
		info = colors.WHITE .. ":: ",
		prompt = colors.WHITE .. "=> ",
		warn = colors.YELLOW .. "WARN" .. colors.WHITE .. ": ",
		error = colors.RED .. "ERROR" .. colors.WHITE .. ": ",
	},
	suffix = colors.RESET
}

function validate_packages_exist(pkgs, transaction)
  local handle = io.popen("apk query " .. table.concat(pkgs, " ") .. " --format json")
	local raw = handle:read("*a")
	handle:close()
	local pkgs_raw = json.decode(raw)
  local requested = {}
	for _, name in ipairs(pkgs) do
		requested[name] = true
  end
  for _, pkg in ipairs(pkgs_raw) do
		requested[pkg.name] = nil
  end
  local missing = {}
	for name in pairs(requested) do
		table.insert(missing, name)
	end
  if #missing > 0 then
		transaction:fatal("Missing packages: " .. table.concat(missing, ", "), 1)
  end
	transaction:verbose("All packages were found.")
end

function query_pkg_index_installed(pkgs, transaction)
	transaction:verbose("Calling `apk query " .. table.concat(pkgs, " ") .. " --installed --format json`")
	local handle = io.popen("apk query " .. table.concat(pkgs, " ") .. " --installed --format json")
	local raw = handle:read("*a")
	handle:close()
	transaction:verbose("Call finished, parsing output")
	local pkgs_raw = json.decode(raw)
	local index = {}
	for _, pkg in ipairs(pkgs_raw) do
		index[pkg.name] = pkg
	end
	transaction:verbose("Searching query data for packages: " .. table.concat(pkgs, ", "))
	for _, pkg in ipairs(pkgs) do
		if not index[pkg] then
			transaction:error("Could not find a package named " .. pkg)
			os.exit(1)
		end
	end
	return
end

function createTransaction()
	local transaction = {
		active_multi = false
	}
	
	-- base
	function transaction:verbose(msg)
		if args.verbose then
			io.write(log.prefix.verbose .. msg .. "\n" .. log.suffix)
			io.flush()
		end
	end
	function transaction:log(msg)
		io.write(log.prefix.info .. msg .. "\n" .. log.suffix)
		io.flush()
	end
	function transaction:warn(msg)
		io.write(log.prefix.warn .. msg .. "\n" .. log.suffix)
		io.flush()
	end
	function transaction:error(msg)
		io.write((transaction.active_multi and "\n" or "") .. log.prefix.error .. msg .. "\n" .. log.suffix)
		io.flush()
	end

	-- multi
	function transaction:multi(msg)
		if not args.verbose then
			transaction.active_multi = true
			io.write(log.prefix.info .. msg)
			io.flush()
			local ret = {}
			function ret:add(msg)
				io.write(" " .. msg)
				io.flush()
			end
			function ret:finish(msg)
				io.write(" " .. msg .. "\n" .. log.suffix)
				io.flush()
				transaction.active_multi = false
			end
			return ret
		else -- verbose output can interfere with multi
			transaction:log(msg)
			local ret = {}
			function ret:add(msg)
				transaction:log(msg)
			end
			function ret:finish(msg)
				transaction:log(msg)
			end
			return ret
		end
	end

	-- exit functions
	function transaction:finish(msg)
		self:log(msg)
		os.exit(0)
	end
	function transaction:fatal(msg, code)
		self:error(msg)
		os.exit(code or 1)
	end

	-- prompts
	function transaction:prompt(msg)
		io.write(log.prefix.prompt .. msg .. ": " .. log.suffix)
		io.flush()
		return io.read()
	end
	function transaction:confirm(msg, default)
		io.write(log.prefix.prompt .. msg .. " " .. (default and "[Y/n]: " or "[y/N]: ") .. log.suffix)
		io.flush()
		if not args.yes then
			local input = io.read()
			if not input then
				return default and true or false
			end
			input = input:lower():gsub("%s+", "")
			if input == "" then
				return default and true or false
			end
			return input == "y" or input == "yes"
    else
			io.write("y\n")
			io.flush()
			return true
		end
	end

	-- command execution
	function transaction:exec(cmd, cmd_args, callback)
		transaction:verbose("Running command: " .. cmd .. " " .. table.concat(cmd_args, " "))
		uv.spawn(cmd, {
			args = cmd_args,
			stdio = { 0, 1, 2 }
		}, callback)
		uv.run()
	end

	function transaction:exec_privileged(cmd, cmd_args, callback)
		if args.auth_tool ~= "" then
			transaction:verbose("Running command as privelidged: " .. args.auth_tool .. " " .. cmd .. " " .. table.concat(cmd_args, " "))
			uv.spawn(args.auth_tool, {
				args = { cmd, table.unpack(cmd_args) },
				stdio = { 0, 1, 2 }
			}, callback)
		else
			if uv.getuid() ~= 0 then
				transaction:fatal("Cannot use no privelidge escalation helper without running as root", 1)
			else
				transaction:verbose("Running command as root: " .. cmd .. " " .. table.concat(cmd_args, " "))
				uv.spawn(base, {
					args = cmd_args,
					stdio = { 0, 1, 2 }
				}, callback)
			end
		end
		uv.run()
	end
	
	return transaction
end

function split(str, sep)
  local result = {}
  local pattern = "(.-)" .. sep
  local last_end = 1
  for part, pos in string.gmatch(str, "(.-)" .. sep .. "()") do
		table.insert(result, part)
		last_end = pos
  end
  table.insert(result, str:sub(last_end))
  return result
end

if args.command == "install" then
	local transaction = createTransaction()
	local query = transaction:multi("Querying package index...")
	local index = validate_packages_exist(args.packages, transaction)
	query:finish("done")
	transaction:log("The following packages will be installed: " .. table.concat(args.packages, ", "))
	local prompt = transaction:confirm("Install them?", true)
	if prompt then
		transaction:exec_privileged("apk", { "add", table.unpack(args.packages) }, function(code, signal)
			if code == 0 then
				transaction:finish("Transaction completed!")
			else
				transaction:fatal("Transaction failed with code: " .. code, code)
			end
		end)
	else
		transaction:fatal("Transaction aborted by user", 1)
	end
elseif args.command == "uninstall" then
	local transaction = createTransaction()
	local query = transaction:multi("Querying installed packages...")
	local index = query_pkg_index_installed(args.packages, transaction, query)
	query:finish("done")
	transaction:log("The following packages will be unstalled: " .. table.concat(args.packages, ", "))
	local prompt = transaction:confirm("Uninstall them?", true)
	if prompt then
		transaction:exec_privileged("apk", { "del", table.unpack(args.packages) }, function(code, signal)
			if code == 0 then
				transaction:finish("Transaction completed!")
			else
				transaction:fatal("Transaction failed with code: " .. code, code)
			end
		end)
		uv.run()
	else
		transaction:fatal("Transaction aborted by user", 1)
	end
elseif args.command == "update" then
	local transaction = createTransaction()
	transaction:log("Updating package index...")
	transaction:exec_privileged("apk", { "update" }, function(code, signal)
		if code == 0 then
			if args.repos then
				transaction:finish("Package index updated!")
			end
		else
			transaction:fatal("Transaction failed with code: " .. code, code)
		end
	end)
	if not args.repos then
		transaction:log("Updating system...")
		transaction:exec_privileged("apk", { "upgrade" }, function(code, signal)
			if code == 0 then
				transaction:finish("System updated!")
			else
				transaction:fatal("Transaction failed with code: " .. code, code)
			end
		end)
	end
end
