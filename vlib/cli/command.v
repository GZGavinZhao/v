module cli

type FnCommandCallback = fn (cmd Command) ?
type ArgResult = bool | int | []int | string | []string | flloat | []float

// str returns the `string` representation of the callback.
pub fn (f FnCommandCallback) str() string {
	return 'FnCommandCallback=>' + ptr_str(f)
}

// Command is a structured representation of a single command
// or chain of commands.
pub struct Command {
pub mut:
	name            string
	usage           string
	description     string
	version         string
	pre_execute     FnCommandCallback
	execute         FnCommandCallback
	post_execute    FnCommandCallback
	disable_help    bool
	disable_version bool
	disable_flags   bool
	sort_flags      bool
	sort_commands   bool
	parent          &Command = 0
	commands        []Command
	flags           []Flag
	required_args   int
	args            []string
}

// str returns the `string` representation of the `Command`.
pub fn (cmd Command) str() string {
	mut res := []string{}
	res << 'Command{'
	res << '	name: "$cmd.name"'
	res << '	usage: "$cmd.usage"'
	res << '	version: "$cmd.version"'
	res << '	description: "$cmd.description"'
	res << '	disable_help: $cmd.disable_help'
	res << '	disable_flags: $cmd.disable_flags'
	res << '	disable_version: $cmd.disable_version'
	res << '	sort_flags: $cmd.sort_flags'
	res << '	sort_commands: $cmd.sort_commands'
	res << '	cb execute: $cmd.execute'
	res << '	cb pre_execute: $cmd.pre_execute'
	res << '	cb post_execute: $cmd.post_execute'
	if cmd.parent == 0 {
		res << '	parent: &Command(0)'
	} else {
		res << '	parent: &Command{$cmd.parent.name ...}'
	}
	res << '	commands: $cmd.commands'
	res << '	flags: $cmd.flags'
	res << '	required_args: $cmd.required_args'
	res << '	args: $cmd.args'
	res << '}'
	return res.join('\n')
}

// is_root returns `true` if this `Command` has no parents.
pub fn (cmd Command) is_root() bool {
	return isnil(cmd.parent)
}

// root returns the root `Command` of the command chain.
pub fn (cmd Command) root() Command {
	if cmd.is_root() {
		return cmd
	}
	return cmd.parent.root()
}

// full_name returns the full `string` representation of all commands int the chain.
pub fn (cmd Command) full_name() string {
	if cmd.is_root() {
		return cmd.name
	}
	return cmd.parent.full_name() + ' $cmd.name'
}

// add_commands adds the `commands` array of `Command`s as sub-commands.
pub fn (mut cmd Command) add_commands(commands []Command) {
	for command in commands {
		cmd.add_command(command)
	}
}

// add_command adds `command` as a sub-command of this `Command`.
pub fn (mut cmd Command) add_command(command Command) {
	mut subcmd := command
	if cmd.commands.contains(subcmd.name) {
		println('Command with the name `$subcmd.name` already exists')
		exit(1)
	}
	subcmd.parent = unsafe { cmd }
	cmd.commands << subcmd
}

// setup ensures that all sub-commands of this `Command`
// is linked as a chain.
pub fn (mut cmd Command) setup() {
	for mut subcmd in cmd.commands {
		subcmd.parent = unsafe { cmd }
		subcmd.setup()
	}
}

// add_flags adds the array `flags` to this `Command`.
pub fn (mut cmd Command) add_flags(flags []Flag) {
	for flag in flags {
		cmd.add_flag(flag)
	}
}

// add_flag adds `flag` to this `Command`.
pub fn (mut cmd Command) add_flag(flag Flag) {
	if cmd.flags.contains(flag.name) {
		println('Flag with the name `$flag.name` already exists')
		exit(1)
	}
	cmd.flags << flag
}

// parse parses `args` into this structured `Command`.
pub fn (mut cmd Command) parse(args []string) {
	if !cmd.disable_flags {
		cmd.add_default_flags()
	}
	cmd.add_default_commands()
	if cmd.sort_flags {
		cmd.flags.sort(a.name < b.name)
	}
	if cmd.sort_commands {
		cmd.commands.sort(a.name < b.name)
	}
	cmd.args = args[1..]
	if !cmd.disable_flags {
		cmd.parse_flags()
	}
	cmd.parse_commands()
}

// add_default_flags adds the commonly used `-h`/`--help` and
// `-v`/`--version` flags to the `Command`.
fn (mut cmd Command) add_default_flags() {
	if !cmd.disable_help && !cmd.flags.contains('help') {
		use_help_abbrev := !cmd.flags.contains('h') && cmd.flags.have_abbrev()
		cmd.add_flag(help_flag(use_help_abbrev))
	}
	if !cmd.disable_version && cmd.version != '' && !cmd.flags.contains('version') {
		use_version_abbrev := !cmd.flags.contains('v') && cmd.flags.have_abbrev()
		cmd.add_flag(version_flag(use_version_abbrev))
	}
}

// add_default_commands adds the command functions of the
// commonly used `help` and `version` flags to the `Command`.
fn (mut cmd Command) add_default_commands() {
	if !cmd.disable_help && !cmd.commands.contains('help') && cmd.is_root() {
		cmd.add_command(help_cmd())
	}
	if !cmd.disable_version && cmd.version != '' && !cmd.commands.contains('version') {
		cmd.add_command(version_cmd())
	}
}

fn (mut cmd Command) parse_flags() {
	for {
		if cmd.args.len < 1 || !cmd.args[0].starts_with('-') {
			break
		}
		mut found := false
		for i in 0 .. cmd.flags.len {
			unsafe {
				mut flag := &cmd.flags[i]
				if flag.matches(cmd.args, cmd.flags.have_abbrev()) {
					found = true
					flag.found = true
					cmd.args = flag.parse(cmd.args, cmd.flags.have_abbrev()) or {
						println('Failed to parse flag `${cmd.args[0]}`: $err')
						exit(1)
					}
					break
				}
			}
		}
		if !found {
			println('Command `$cmd.name` has no flag `${cmd.args[0]}`')
			exit(1)
		}
	}
}

fn (mut cmd Command) parse_commands() {
	global_flags := cmd.flags.filter(it.global)
	cmd.check_help_flag()
	cmd.check_version_flag()
	for i in 0 .. cmd.args.len {
		arg := cmd.args[i]
		for j in 0 .. cmd.commands.len {
			mut command := cmd.commands[j]
			if command.name == arg {
				for flag in global_flags {
					command.add_flag(flag)
				}
				command.parse(cmd.args[i..])
				return
			}
		}
	}
	if cmd.is_root() && isnil(cmd.execute) {
		if !cmd.disable_help {
			cmd.execute_help()
			return
		}
	}
	// if no further command was found, execute current command
	if cmd.required_args > 0 {
		if cmd.required_args > cmd.args.len {
			eprintln('Command `$cmd.name` needs at least $cmd.required_args arguments')
			exit(1)
		}
	}
	cmd.check_required_flags()
	if !isnil(cmd.pre_execute) {
		cmd.pre_execute(*cmd) or {
			eprintln('cli preexecution error: $err')
			exit(1)
		}
	}
	if !isnil(cmd.execute) {
		cmd.execute(*cmd) or {
			eprintln('cli execution error: $err')
			exit(1)
		}
	}
	if !isnil(cmd.post_execute) {
		cmd.post_execute(*cmd) or {
			eprintln('cli postexecution error: $err')
			exit(1)
		}
	}
}

fn (cmd Command) check_help_flag() {
	if !cmd.disable_help && cmd.flags.contains('help') {
		help_flag := cmd.flags.get_bool('help') or { return } // ignore error and handle command normally
		if help_flag {
			cmd.execute_help()
			exit(0)
		}
	}
}

fn (cmd Command) check_version_flag() {
	if !cmd.disable_version && cmd.version != '' && cmd.flags.contains('version') {
		version_flag := cmd.flags.get_bool('version') or { return } // ignore error and handle command normally
		if version_flag {
			version_cmd := cmd.commands.get('version') or { return } // ignore error and handle command normally
			version_cmd.execute(version_cmd) or { panic(err) }
			exit(0)
		}
	}
}

fn (cmd Command) check_required_flags() {
	for flag in cmd.flags {
		if flag.required && flag.value.len == 0 {
			full_name := cmd.full_name()
			println('Flag `$flag.name` is required by `$full_name`')
			exit(1)
		}
	}
}

// execute_help executes the callback registered
// for the `-h`/`--help` flag option.
pub fn (cmd Command) execute_help() {
	if cmd.commands.contains('help') {
		help_cmd := cmd.commands.get('help') or { return } // ignore error and handle command normally
		help_cmd.execute(help_cmd) or { panic(err) }
	} else {
		print(cmd.help_message())
	}
}

fn (cmds []Command) get(name string) ?Command {
	for cmd in cmds {
		if cmd.name == name {
			return cmd
		}
	}
	return error('Command `$name` not found in $cmds')
}

fn (cmds []Command) contains(name string) bool {
	for cmd in cmds {
		if cmd.name == name {
			return true
		}
	}
	return false
}

pub fn (mut cmd Command) parse() {

}

pub fn (mut cmd Command) run() {
	cmd.setup()
	cmd.parse()
}