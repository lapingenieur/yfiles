module main

import term
import term.termios
import os
import time

////// TODOS
// execution internal timeout -> fork so prompt exits when child exits
// kill ssh process according to prompt

fn join_array[T](array []T) string {
	if array.len == 0 { return "[none]" }
	mut outs := array[0].str()
	for i in array[1..] {
		outs += ", $i"
	}
	return outs
}

//// ParseArgsSt
struct ParseArgsSt {
pub:
	array []string
pub mut:
	idx int
}
fn (mut self ParseArgsSt) next_or_blank() ?string {
	if self.idx >= self.array.len {
		return none
	}
	defer { self.idx += 1 }
	return self.array[self.idx]
}
fn (mut self ParseArgsSt) next() ?string {
	mut out := self.next_or_blank() or { return none }
	for out == "" {
		out = self.next_or_blank() or { return none }
	}
	return out
}
fn (self ParseArgsSt) get() string {
	return self.array[self.idx]
}

//// AddressData
enum PasswordMode {
	entry
	ask
	empty
	command
}
type PasswordString = string
fn (self PasswordString) str() string {
	return '[password-data is hidden]'
}
fn (self PasswordString) get() string {
	return self
}
struct AddressData {
pub mut:
	address string
	password PasswordString
	password_command string
	password_mode PasswordMode
	origin string
	options_int map[string]int
	ports [][]u64 = [][]u64{cap: 5}
}
enum AddPortStatus {
	ok = 0
	single
	first
	second
}
fn (mut self AddressData) add_port(port_str string) AddPortStatus {
	array := port_str.split(":")

	mut ports := []u64{cap:2}
	if array.len == 1 {
		ports << [port_str.parse_uint(10, 64) or {
			return .single
		}]
	} else {
		ports << [array[0].parse_uint(10, 64) or {
			return .first
		}]
		ports << [array[1].parse_uint(10, 64) or {
			return .second
		}]
	}

	self.ports << ports
	return .ok
}
fn (self AddressData) str_port(idx int) string {
	return if self.ports[idx].len == 1 {
		"${self.ports[idx][0]}"
	} else {
		"${self.ports[idx][0]}:${self.ports[idx][1]}"
	}
}

//// ConfigData
enum ProceedType {
	proceed
	end
	list
	list_all
}
struct ConfigData {
pub mut:
	addresses map[string]AddressData = map[string]AddressData
	run_addresses []string
	commands map[string]string

	options_int map[string]int = { "timeout": 4 }

	proceed ProceedType
	loaded_configs []string

	log Log
}

//// Custom Logging Interface
enum LogLevel {
	silent = 0
	error
	warn
	info
	debug
}
struct Log {
pub mut:
	level LogLevel = .warn
}

fn (self Log) log(pfx string, msg string, cfn fn(string) string) {
	prefix := term.ecolorize(cfn, pfx)
	message := msg.replace("\n", "\n$prefix ")
	eprintln("$prefix $message")
}
fn (self Log) print(msg string) {
	if int(self.level) != 0 {
		print(msg)
	}
}
fn (self Log) println(msg string) {
	if int(self.level) != 0 {
		println(msg)
	}
}
fn (self Log) error(orig string, msg string) {
	if int(self.level) >= int(LogLevel.error) {
		self.log("$orig/error:", msg, term.red)
	}
}
fn (self Log) warn(orig string, msg string) {
	if int(self.level) >= int(LogLevel.warn) {
		self.log("$orig/warn:", msg, term.yellow)
	}
}
fn (self Log) info(orig string, msg string) {
	if int(self.level) >= int(LogLevel.info) {
		self.log("$orig/info:", msg, term.green)
	}
}
fn (self Log) debug(orig string, msg string) {
	if int(self.level) >= int(LogLevel.debug) {
		self.log("$orig/debug:", msg, term.cyan)
	}
}

//// End of Log

enum Help {
	default
	usage
	config
	profile
	options
}

fn help(page Help) {
	version := "1.4"

	println("sshtpt - SSH TCP-Port Tunnelling Tool (v$version)")

	match page {
		.default { println("
create reverse SSH tunnels that forward distant TCP ports to local ports
usage: sshtpt [ARG...]

for more information, use 'sshtpt help PAGE' where PAGE is one of:
  usage : help about generic usage
  profile : help about address profiles
  config : help about the configuration
  options : help about the options and settings

verbosing arguments are:
  --debug : debuggingly verbosive
  --verbose : verbosive
  (default) : prints warnings
  --no-warn, --quiet : only errors
  --silent : almost no output")
		}
		.usage { println("help/usage:

introduction:
  sshtpt sets up port forwarding through SSH for a use-indicated list of profiles (see profile-help)
  ssh connections may require passwords, but we encourage users to set up ssh-keys instead

sshtpt ports standards:
  an sshtpt port-declaration looks like NN:MM where NN is the local port and MM the remote port (integers)
  when NN and MM are equal, this expression is simplified as NN (no colon separator)
  examples: 5173:6666 (remote 6666 and local 5173), 9956 (remote and local 9956)

basic CLI arguments:
  -a, --address ADDRESS PORTS...
	specify and configure an new anonymous profile to use within the CLI (ADDRESS is either a url or an IPv4)
	this appends the entered profile to the tasklist and selects it for the following arguments
	this profile will not be saved to any file and will vanish after the execution ended
  --add PROFILE...
	appends the specified profiles to the tasklist and selects the last one for the following arguments
	the referenced profiles shall be defined in either loaded configuration files
  --port, --ports PORTS...
	explicits that the next arguments are port declarations
	this is useful when the user wants to modify a loaded profile for this execution only
  --use FILE...
	read the specified configuration file
	FILE is either the name of a file in the configuration directory, or a valid path

for password management, see the help for profiles (help profile)")
		}
		.profile { println ("help/profiles

sshtpt profiles:
  a profile consists of an address (url or IPv4) and a list of ports (see 'ports standards' in usage-help)
  profiles can be defined in configuration files (see configuration-help) or via CLI arguments (see usage-help)
  the user indicates which profiles to set up when executing the command

profile CLI arguments:
  --list
	print a list of the loaded profiles
  --list-all
	load all the config files in the config directory and list all the profiles
  these two arguments make sshtpt exit just after their execution
  see also --files in configuration-help

profile-wide configuration:
  as discussed in the 'usage' help page, the user can assign an address and several ports to every profile
  in addition, profiles support options (that, when set, overwrite global options), as well as passwords
  sshtpt don't store any of your passwords on its own, unless you do your stuff in the configuration files
  sshtpt will never store their value, but they can be exposed to different degrees during executions
  it is highly recommended to set up ssh keys to bypass password needs, and use 'password-empty'

password-related arguments (CLI) and directives (config) are the same, except the first have a double dash prefix:
  --password PASSWORD
	(DON'T USE THIS) exposes your password system-wide in the commandline of sshtpt
  --password-ask, --ask-password
	(DEFAULT) asks interactively the user for a password right before the ssh command is launched
  --password-env, --env-password ENV
	the password lives in the environment variable ENV
  --password-empty, --empty-password
	the password shall be empty (might be used when ssh keys are set up)
  --password-location FILE
	read the password from the specified file, either name of a file in ~/.sshtpt/ or valid path
  --password-command CMD
	get the password from CMD's standard output
	CMD is either a valid command or the name of a sshtpt-configured command (see configuration help)")
		}
		.options { println("help/options

options are runtime settings that apply to different things
some are either defined for a profile in particular, of as 'global' options (defaults)
in the list below, options are marked (GLOBAL) or (PROFILE) when they only apply globally or to a profile
for both CLI arguments and config directives, the parameters and <optcmd> NAME VALUE

          .------------------------------------------.
          |                                          |
.-------. |              Setting Options             |
|\\ type  \\|                                          |
| '----.  +---------------+--------------------------+
| range \\ | CLI arguments | config directives        |
+---------+---------------+--------------------------+
| global  | -g, --global  | global: NAME VAL         |
+---------+---------------+--------------------------+
| profile | -o, --option  | profile: option NAME VAL |
'---------'---------------'--------------------------'

list of options:
  timeout
	sets ssh '-o ConnectTimeout' to the specified value (in seconds)
	0 means no timeout, >0 means wait VALUE seconds for the remote address to respond a connection before exiting") }
		.config { println("help/config

configuration:
  the main config file is XDG_CONFIG/sshtpt/main.conf, where XDG_CONFIG stands for the user configuration directory;
  it is read at each execution of sshtpt, therefore it should not contain too many things to interprete;
  other files with `.conf` extention can stay in this directory and can be interpreted if the user explicitely
  indicates in the CLI arguments or with the include-config instructions

config CLI arguments:
  --files
	list the config files found in the config directory
  see also --list and --list-all in profiles-help

config file syntax:
  a man-like description would be: ( DIR [: ARG...] ; )...
  - an instruction consists of a directive (DIR) with or without arguments (ARG...)
  - directives are separated from their potential arguments by a colon (:)
  - an instruction must end with a semi colon (;), it is placed right after the directive if there's no argument
  - the arguments are separated by any of the space-like character (space, \\n, \\t, \\v, \\f and \\r)
  - one argument shall not contain any space-like character
  - an instruction can span several lines as long as it respects the upper described needs
  - instructions that start with #, // or with the comment directive are considered comments and are skipped
  - comments should be considered as instructions: they should not contain any semi colon except needed the closing one
  - as for instructions, comments can span several lines, everything is ignored until a semi colon is found
  !! be aware that sshtpt will return an error if one of the specified config files contain errors

list of config directives:
  address,
  profile: ADDRESS [ARG [PARAM]...]...
    define a new address profile with address ADDRESS (name will be set to ADDRESS as well)
    arguments:
      ports, port PORT...
        append a PORT to the list of ports
      name NAME
        set the profile name to NAME
	  option OPT VALUE
		set the OPT profile-option to VALUE
    plus those explained in the profile-help page
  use,
  include: FILE...
	like the --use CLI argument: specify config files to read and include *after* having read the current file
  add: PROFILE...
	like the --add CLI argument; you shouldn't use this in main.conf")
		}
	}
}

//// ArgDecodeModes used as buffer
enum ArgDecodeModes {
	zero
	ports
	use
	add
}

fn get_args(mut config &ConfigData) !ConfigData {
	mut address := ""

	mut args := ParseArgsSt {
		array: os.args[1..]
		idx: 0
	}
	mut mode := ArgDecodeModes.zero
	for {
		arg := args.next() or {
			break
		}

        match arg {
            "--help", "-h" {
					help(.default)
					config.proceed = .end
				}
			"help" {
				match args.next() or { "default" } {
					"usage" { help(.usage) }
					"profile", "profiles" { help(.profile) }
					"option", "options" { help(.options) }
					"config" { help(.config) }
					else {
						help(.default)
					}
				}

				config.proceed = .end
			}
			"--list" {
				config.proceed = .list
			}
			"--list-all" {
				config.proceed = .list_all
			}
			"--debug", "--verbose", "--no-warn", "--quiet", "--silent" {}
			"--address", "-a" {
				param := args.next() or {
					config.log.error("args", "missing parameter for argument ${args.idx} '${arg}'")
					return error("")
				}

				address = param
				if _ := config.addresses[param] {
					continue
				}
				config.addresses[param] = AddressData { address: address, origin: "args" }
				config.run_addresses << address
				mode = .ports
			}
			"--global", "-g" {
				opt := args.next() or {
					config.log.error("args", "missing parameter for argument ${args.idx} '${arg}'")
					return error("")
				}

				match opt {
					"timeout" {
						timeout := args.next() or {
							config.log.error("args", "missing parameter for option '$opt' of argument $args.idx '$arg'")
							return error("")
						}
						config.options_int["timeout"] = int(timeout.parse_int(10, 0) or {
							config.log.error("config", "expected numeric option for parameter timeout of argument $args.idx '$arg'")
							return error("")
						})
					}
					else {
						config.log.error("args", "unknown parameter '$opt' for argument $args.idx '${arg}'")
						return error("")
					}
				}
			}
			"--option", "-o" {
				if address == "" {
					config.log.error("args", "expected argument '--address ADDRESS' before argument $args.idx $arg specified")
					return error("")
				}

				opt := args.next() or {
					config.log.error("args", "missing option for argument ${args.idx} '${arg}'")
					return error("")
				}

				match opt {
					"timeout" {
						timeout := args.next() or {
							config.log.error("args", "missing value for option '$opt' of argument $args.idx '$arg'")
							return error("")
						}
						config.addresses[address].options_int["timeout"] = int(timeout.parse_int(10, 0) or {
							config.log.error("config", "expected numeric value for option timeout of argument $args.idx '$arg'")
							return error("")
						})
					}
					else {
						config.log.error("args", "unknown option '$opt' for argument $args.idx '${arg}'")
						return error("")
					}
				}
			}
			"--ports", "--port" {
				mode = .ports
			}
			"--use" {
				mode = .use
			}
			"--add" {
				mode = .add
			}
			"--command" {
				name := args.next() or {
					config.log.error("args", "missing parameter #1 (name) for argument $args.idx '$arg'")
					return error("")
				}
				config.commands[name] = args.next() or {
					config.log.error("args", "missing parameter #2 (command) for argument $args.idx '$arg'")
					return error("")
				}
			}
			"--password-cmd", "--password-command" {
				if address == "" {
					config.log.error("args", "expected argument '--address ADDRESS' before argument $args.idx $arg specified")
					return error("")
				}

				config.addresses[address].password_command = args.next() or {
					config.log.error("args", "missing parameter for argument $args.idx '$arg'")
					return error("")
				}
				config.addresses[address].password_mode = .command
			}
			"--password" {
				if address == "" {
					config.log.error("args", "expected argument '--address ADDRESS' before argument $args.idx $arg specified")
					return error("")
				}

				param := args.next() or {
					config.log.error("args", "missing parameter for argument ${args.idx} '${arg}'")
					return error("")
				}

				config.log.warn("args", "you shouldn't indicate your passwords in the commandline")
				config.log.warn("args", "=> prefer defining them in special config files (see help/config) or using --ask-password argument")

				config.addresses[address].password = param
			}
			"--empty-password", "--password-empty" {
				if address == "" {
					config.log.error("args", "expected argument '--address ADDRESS' before argument $args.idx $arg specified")
					return error("")
				}

				config.addresses[address].password_mode = .empty
			}
			"--ask-password", "--password-ask" {
				if address == "" {
					config.log.error("args", "expected argument '--address ADDRESS' before argument $args.idx $arg specified")
					return error("")
				}

				config.addresses[address].password_mode = .ask
			}
			"--env-password", "--password-env" {
				if address == "" {
					config.log.error("args", "expected argument '--address ADDRESS' before argument $args.idx $arg specified")
					return error("")
				}

				name := args.next() or {
					config.log.error("args", "missing parameter for argument ${args.idx} '${arg}'")
					return error("")
				}
				password := os.getenv_opt(name) or {
					config.log.error("args", "the environment variable '${name}' specified for password-env is currently undeclared for argument ${args.idx} '${arg}'")
					return error("")
				}

				config.addresses[address].password = password
			}
			"--password-location" {
				if address == "" {
					config.log.error("args", "expected argument '--address ADDRESS' before argument $args.idx $arg specified")
					return error("")
				}

				mut location := args.next() or {
					config.log.error("args", "missing password-location parameter for argument ${args.idx} '${arg}'")
					return error("")
				}

				config_xdg := os.config_dir() or {
					config.log.error("config", "unable to find the global configuration directory")
					return error("")
				}
				config_dir := os.join_path_single(config_xdg, "sshtpt")
				if ! os.is_dir(config_dir) {
					config.log.error("config", "unable to find the sshtpt configuration directory (${config_dir})")
					return error("")
				}

				if os.is_file(os.join_path(os.home_dir(), ".sshtpt", location)) {
					location = os.join_path(os.home_dir(), ".sshtpt", location)
				} else if os.is_file(os.join_path(config_dir, location)) {
					location = os.join_path(config_dir, location)
					config.log.warn("args", "password files shouldn't stay in the configuration directory for security reasons")
				} else if ! os.is_file(location) {
					config.log.error("args", "unexisting file '${location}' specified by password-location for argument ${args.idx} '${arg}'")
					return error("")
				}

				password := (os.read_file(location) or {
					config.log.error("args", "failed reading from password-location file '${location}' for argument ${args.idx} '${arg}'")
					return error("")
				}).trim("\n")
				if password.count("\n") != 0 {
					config.log.error("args", "password in file ${location} must be single-instruction for argument ${args.idx} '${arg}'")
					return error("")
				}

				config.addresses[address].password = password
			}
			else {
				match mode {
					.ports {
						if address == "" {
							config.log.error("args", "expected argument '--address ADDRESS' before argument $args.idx $arg specified")
							return error("")
						}

						config.log.debug("args", "adding port $arg to profile $address")
						status := config.addresses[address].add_port(arg)
						if status != .ok {
							text := match status {
								.single { "single" }
								.first { "first of pair" }
								.second { "second of pair" }
								.ok {""}
							}
							config.log.error("args", "invalid argument $args.idx '${arg}', expecting port: non numeric $text value port")
							return error("")
						}
					}
					.add {
						config.run_addresses << arg
						address = arg
					}
					.use {
						config.log.info("args", "reading $arg configuration file now")
						get_config(mut &config, arg) or { return err }
					}
					.zero {
							config.log.error("args", "unknown argument $args.idx '${arg}'")
							return error("")
					}
				}
			}
        }
	}

	return config
}

fn get_config(mut config &ConfigData, filename string) !ConfigData {
	config.log.debug("config", "parsing config for '$filename'")

	config_xdg := os.config_dir() or {
		config.log.error("config", "unable to find the global configuration directory")
		return error("")
	}
	config_dir := os.join_path_single(config_xdg, "sshtpt")
	if ! os.is_dir(config_dir) {
		config.log.error("config", "unable to find the sshtpt configuration directory (${config_dir})")
		return error("")
	}
	mut config_path := os.join_path_single(config_dir, filename + ".conf")
	if ! os.is_file(config_path) {
		config_path = os.join_path_single(config_dir, filename)
		if ! os.is_file(config_path) {
			config_path = filename
			if ! os.is_file(config_path) {
				config.log.error("config", "unable to find `$filename` configuration file")
				return error("")
			}
		}
	}

	if config_path in config.loaded_configs {
		config.log.info("config", "skipping already loaded configuration file '$filename'")
		return config
	} else {
		config.loaded_configs << config_path
	}

	config_instructions := (os.read_file(config_path) or {
		config.log.error("config", "unable to read `$config_path` configuration file")
		return error("")
	}).split(";")

	mut include_files := []string{} // inluded files are read after finished reading the current file

	for i, instruction in config_instructions {
		if instruction.contains(":") {
			mut directive, mut value := instruction.split_once(":")
			directive = directive.trim_space()
			value = value.trim_space()

			mut args := ParseArgsSt {
				array: value.split_any(" \t\v\f\r\n")
				idx: 0
			}

			match directive {
				"", "comment" { continue }
				"add" {
					config.run_addresses << args.next() or {
						config.log.error("args", "missing argument for $directive directive at instruction $i of '$filename' configuration file")
						return error("")
					}
					for {
						config.run_addresses << args.next() or { break }
					}
				}
				"use", "include" {
					if filename == "main.conf" {
						config.log.warn("config", "you shouldn't include other configuration files from your main.conf configuration; prefer the CLI '--use CONFIG' argument")
					}
					mut param := args.next() or {
						config.log.error("config", "missing argument for $directive directive at instruction $i of '$filename' configuration file")
						return error("")
					}
					include_files << param
					config.log.info("config", "defered reading ${param} configuration file")
					for {
						param = args.next() or { break }
						include_files << param
						config.log.info("config", "defered reading ${param} configuration file")
					}
				}
				"global" {
					opt := args.next() or {
						config.log.error("config", "missing argument for directive $directive at instruction ${i} of '$filename' configuration file")
						return error("")
					}

					match opt {
						"timeout" {
							timeout := args.next() or {
								config.log.error("config", "missing argument for option $opt at instruction ${i} of '$filename' configuration file")
								return error("")
							}
							config.options_int["timeout"] = int(timeout.parse_int(10, 0) or {
								config.log.error("config", "expected numeric value for option $opt at instruction ${i} of '$filename' configuration file")
								return error("")
							})
						}
						else {
							config.log.error("config", "unknown option '$opt' for directive $directive at instruction ${i} of '$filename' configuration file")
							return error("")
						}
					}
				}
				"command" {
					name := args.next() or {
						config.log.error("config", "missing argument #1 (name) for $directive directive at instruction $i of '$filename' configuration file")
						return error("")
					}
					if args.array.len < args.idx {
						config.log.error("config", "missing arguments for $directive directive at instruction $i of '$filename' configuration file")
						return error("")
					}

					config.commands[name] = value.trim_string_left(name).trim_space()
				}
				"address", "profile" {
					mut name := args.next() or {
						config.log.error("config", "missing arguments for $directive directive at instruction $i of '$filename' configuration file")
						return error("")
					}
					mut address_template := AddressData { address: name, origin: "config:$filename" }

					mut mode_port := false
					for {
						arg := args.next() or {
							break
						}

						match arg {
							"ports", "port" { mode_port = true }
							"option" {
								opt := args.next() or {
									config.log.error("config", "missing option for $arg at instruction ${i} of '$filename' configuration file")
									return error("")
								}

								match opt {
									"timeout" {
										timeout := args.next() or {
											config.log.error("config", "missing value for option $opt at instruction ${i} of '$filename' configuration file")
											return error("")
										}
										address_template.options_int["timeout"] = int(timeout.parse_int(10, 0) or {
											config.log.error("config", "expected numeric value for option $opt at instruction ${i} of '$filename' configuration file")
											return error("")
										})
									}
									else {
										config.log.error("config", "unknown option '$opt' for argument $arg at instruction ${i} of '$filename' configuration file")
										return error("")
									}
								}
							}
							"name" {
								name = args.next() or {
									config.log.error("config", "missing arguments for name at instruction ${i} of '$filename' configuration file")
									return error("")
								}
							}
							"password-location" {
								mut location := args.next() or {
									config.log.error("config", "missing arguments for password-location at instruction ${i} of '$filename' configuration file")
									return error("")
								}

								if os.is_file(os.join_path(os.home_dir(), ".sshtpt", location)) {
									location = os.join_path(os.home_dir(), ".sshtpt", location)
								} else if os.is_file(os.join_path(config_dir, location)) {
									location = os.join_path(config_dir, location)
									config.log.warn("config", "password files shouldn't stay in the configuration directory for security reasons")
								} else if ! os.is_file(location) {
									config.log.error("config", "unexisting file '${location}' specified by password-location at instruction ${i} of '$filename' configuration file")
									return error("")
								}

								password := (os.read_file(location) or {
									config.log.error("config", "failed reading from password-location file '${location}' at instruction ${i} of '$filename' configuration file:\n   ${err}")
									return error("")
								}).trim("\n")
								if password.count("\n") != 0 {
									config.log.error("config", "password in file ${location} must be single-line at instruction ${i} of '$filename' configuration file")
									return error("")
								}
								address_template.password = password
							}
							"password-env", "env-password" {
								param := args.next() or {
									config.log.error("config", "missing argument for password-env at instruction ${i} of '$filename' configuration file")
									return error("")
								}
								password := os.getenv_opt(param) or {
									config.log.error("config", "the environment variable '${name}' specified for password-env is currently undeclared at instruction ${i} of '$filename' configuration file")
									return error("")
								}
								address_template.password = password
							}
							"empty-password", "password-empty" {
								address_template.password_mode = .empty
							}
							"password-ask", "ask-password" {
								address_template.password_mode = .ask
							}
							"password-cmd", "password-command" {
								address_template.password_command = args.next() or {
									config.log.error("config", "missing $directive argument at instruction ${i} '${instruction}' of main.conf")
									return error("")
								}
								address_template.password_mode = .command
							}
							"password" {
								address_template.password = args.next() or {
									config.log.error("config", "missing password argument at instruction ${i} '${instruction}' of main.conf")
									return error("")
								}
								address_template.password_mode = .entry
							}
							else {
								if mode_port {
									status := address_template.add_port(arg)
									if status != .ok {
										text := match status {
											.single { "single" }
											.first { "first of pair" }
											.second { "second of pair" }
											.ok {""}
										}
										config.log.error("config", "invalid argument '${arg}' at instruction $i of '$filename' configuration file, expecting port: non numeric $text value port")
										return error("")
									}
								} else {
									config.log.error("config", "expected argument 'ports' before any ports specified at instruction ${i} of '$filename' configuration file")
									return error("")
								}
							}
						}
					}

					if name in config.addresses {
						config.log.info("config", "run-time merging of address template for profile $name with main config entry at instruction $i of '$filename' configuration file")

						if config.addresses[name].address != address_template.address {
							config.log.warn("config", "unmatching address for profile $name at instruction $i of '$filename' configuration file: (no change applied)\n   read $address_template.address, not ${config.addresses[name].address}")
						}
						if config.addresses[name].password != address_template.password && address_template.password != "" {
							config.log.warn("config", "unmatching password for profile $name at instruction $i of '$filename' configuration file: (no change applied) [password-data is hidden]")
						}
						if config.addresses[name].password_command != address_template.password_command && address_template.password_command != "" {
							config.log.warn("config", "unmatching password-command for profile $name at instruction $i of '$filename' configuration file: (no change applied)\n   read $address_template.password_command, not ${config.addresses[name].password_command}")
						}
						if config.addresses[name].password_mode != address_template.password_mode && address_template.password_mode != .entry {
							config.log.warn("config", "unmatching password-mode for profile $name at instruction $i of '$filename' configuration file: (no change applied)\n   read $address_template.password_command, not ${config.addresses[name].password_command}")
						}

						config.addresses[name].origin += "&config:$filename"

						for opt, val in address_template.options_int {
							if opt in config.addresses[name].options_int {
								if config.addresses[name].options_int[opt] != val {
									config.log.warn("config", "unmatching option $opt for profile $name at instruction $i of '$filename' configuration file: (no change applied)\n   read $val, not ${config.addresses[name].options_int[opt]}")
								}
							} else {
								config.addresses[name].options_int[opt] = val
							}
						}

						for port in address_template.ports {
							if port !in config.addresses[name].ports {
								config.addresses[name].ports << port
							}
						}
					} else {
						config.log.debug("config", "adding address template of profile $name to main config at instruction $i of '$filename' configuration file")
						config.addresses[name] = address_template
					}
				}
				else {
					config.log.error("config", "unknown config directive '${directive}' at instruction ${i} of '$filename' configuration file")
					return error("")
				}
			}
		} else {
			if instruction.trim_space().starts_with("#") || instruction.trim_space().starts_with("//") || instruction.trim_space() == "" { continue }
			else {
				config.log.error("config", "unknown config instruction ${i} of '$filename' configuration file:\n   '$instruction'")
			}
		}
	}

	for include in include_files {
		config = get_config(mut &config, include) or { return err }
	}

	return config
}

fn kill(pid int, log Log) {
	log.debug("kill", "killing PID $pid")

	status := C.kill(pid, C.SIGKILL)

	if status == -1 && C.errno == C.ESRCH {
		log.info("kill", "no process with PID $pid, this process seemingly already exited")
	} else if status == 0 {
		log.info("kill", "killed PID $pid successfully")
	} else {
		log.error("kill", "failed killing PID $pid; errno: ${C.errno}")
	}
}

fn C.vfork() int
fn C.freopen(pathname &char, mode &char, stream C.FILE) C.FILE
fn C.waitpid(pid int, status &int, options int) int
fn C.execvpe(cmd_path &char, argv &&char, envp &&char) int
fn C.execvp(cmd_path &char, argv &&char) int
fn spawnvpec(name string, args []string, envs []string, log Log) int {
	// -c means requires config.log
	mut argv := []&char{cap: args.len + 2}
	argv <<	&char(name.str)
	for i in args {
		argv << &char(i.str)
	}
	argv << &char(0)

	mut envp := []&char{cap: envs.len + 1}
	for i in envs {
		envp << &char(i.str)
	}
	envp << &char(0)

	mut status := int(-1)
	child := C.vfork()
	if child > 0 {
		mut i := 0
		for {
			i++
			time.sleep(time.millisecond * 100)

			mut wstatus := int(0)
			if C.waitpid(child, &wstatus, C.WNOHANG) == child {
				if C.WIFEXITED(wstatus) {
					status = C.WEXITSTATUS(wstatus)
					log.debug("exec", "child returned with status ${status}_u8")
				} else {
					log.warn("exec", "child was returned but didn't call _exit on its own!")
				}
				break
			}

			if i >= 50 {
				if int(log.level) < int(LogLevel.warn) {
					log.error("exec", "killing subcommand because took too much time (>5s) and currently in quiet mode")
					kill(child, log)
					break
				} else {
					log.warn("exec", "command took more than 5 seconds")
					ans := os.input_opt("=> give 5 more seconds following this answer? (yes/exit) => ") or {""}
					match ans.to_lower() {
						"y", "yes" {
							i = 0
							log.debug("exec", "user gave +5 seconds to subcommand")
						}
						"n", "no", "exit" {
							log.warn("exec", "killing the subcommand as order by the user, this will trigger a tunnel creation failure error")
							kill(child, log)
							break
						}
						else {
							log.error("exec", "unknown answer, killing the subcommand, this will trigger a tunnel creation failure error")
							kill(child, log)
							break
						}
					}
				}
			}
		}
	} else {
		status = C.execvpe(argv[0], argv.data, envp.data)
		exit(-1)
	}

	return status
}
fn spawnvph(name string, args []string) int {
	// -h means hidden (no output to sdtout nor stderr)
	mut argv := []&char{cap: args.len + 2}
	argv <<	&char(name.str)
	for i in args {
		argv << &char(i.str)
	}
	argv << &char(0)

	mut status := int(-1)
	child := C.vfork()
	if child > 0 {
		C.waitpid(child, &status, 0)
	} else if child == 0 {
		// no output please!
		C.freopen(&char("/dev/null".str), &char("w".str), C.stdout)
		C.freopen(&char("/dev/null".str), &char("w".str), C.stderr)
		status = C.execvp(argv[0], argv.data)
		exit(-1)
	} else {
		return -1
	}

	return status
}
fn input_hidden(prompt string) !string {
	// better password input than os.input_password: allows empty
	mut old_state := termios.Termios{}
	if termios.tcgetattr(0, mut old_state) != 0 {
		return os.last_error()
	}
	defer {
		termios.tcsetattr(0, C.TCSANOW, mut old_state)
		println("[hidden]")
	}

	mut new_state := old_state
	new_state.c_lflag &= termios.invert(C.ECHO)
	termios.tcsetattr(0, C.TCSANOW, mut new_state)

	return os.input_opt(prompt) or { "" }
}

fn proceed(config &ConfigData) !int {
	config.log.debug("proceed", "checking whether ssh and sshpass are callable commands")
	{
		mut deps := []string{cap: 2}
		if spawnvph("which", ["ssh"]) != 0 {
			config.log.warn("proceed", "ssh is not found in path - is it installed correctly?")
			deps << "ssh"
		}
		if spawnvph("which", ["sshpass"]) != 0 {
			config.log.warn("proceed", "sshpass is not found in PATH - is it installed correctly?")
			deps << "sshpass"
		}

		if deps.len != 0 {
			mut message := deps[0]
			for i in deps[1..] {
				message += ", $i"
			}

			config.log.error("proceed", "unsatisfied required dependencies: $message")
			return error("")
		}
	}

	mut error_count := 0

	for i, name in config.run_addresses {
		config.log.debug("proceed", "proceeding profile #$i '$name'")

		if name !in config.addresses {
			config.log.error("proceed", "$name is not a configured address profile")
			error_count++
			config.log.debug("proceed", "continuing with the next profile")
			continue
		}
		if config.addresses[name].ports.len == 0 {
			config.log.info("proceed", "no port specified for profile $name")
			config.log.debug("proceed", "continuing with the next profile")
			continue
		}

		profile := config.addresses[name]

		mut password := ""
		config.log.debug("proceed", "getting password for profile #$i '$name'")

		if profile.password_mode == .empty  {
			config.log.debug("proceed", "empty password for profile '$name'")
		} else if profile.password_mode == .entry && profile.password != "" {
			password = profile.password
		} else if profile.password_mode == .command {
			if profile.password_command in config.commands {
				config.log.debug("proceed", "using command internally name '${config.commands[profile.password_command]}")
				result := os.execute(config.commands[profile.password_command])
				if result.exit_code != 0 {
					config.log.error("proceed", "extern password command internally named '${profile.password_command}' exited with status $result.exit_code: '${config.commands[profile.password_command]}_u8'")
					config.log.debug("proceed", "continuing with the next profile")
					error_count++
					continue
				}
				password = result.output
			} else {
				result := os.execute(profile.password_command)
				if result.exit_code != 0 {
					config.log.error("proceed", "extern password command '$profile.password_command' exited with status ${result.exit_code}_u8")
					config.log.debug("proceed", "continuing with the next profile")
					error_count++
					continue
				}
				password = result.output
			}
		} else {
			password = input_hidden("Password for profile '$name': ") or {
				config.log.error("proceed", "failed reading password for profile #$i '$name'")
				error_count++
				config.log.debug("proceed", "continuing with the next profile")
				continue
			}
		}

		timeout := if "timeout" in profile.options_int {
			profile.options_int["timeout"]
		} else {
			config.options_int["timeout"]
		}

		plusenv := ["SSHPASS=$password"]

		// important !!! index -2 below should be always empty because port-forwarding gets put there
		mut args := ["-e", "ssh", "-oConnectTimeout=$timeout", "-fNR", "", profile.address]

		for l, port_pair in profile.ports {
			config.log.debug("proceed", "proceeding port #$l $port_pair of profile #$i '$name'")

			if port_pair.len == 1 {
				args[args.len - 2] = "${port_pair[0]}:localhost:${port_pair[0]}"
			} else {
				args[args.len - 2] = "${port_pair[1]}:localhost:${port_pair[0]}"
			}
			mut args_str := args[0]
			for each in args[1..] { args_str += " $each" }

			config.log.info("proceed", "command for port #$l $port_pair of profile #$i '$name': `sshpass $args_str`")
			status := spawnvpec("sshpass", args, plusenv, config.log)
			if status != 0 {
				config.log.error("proceed", "failed tunnel creation for port #$l $port_pair of profile #$i '$name' with status $status")
				error_count++
				config.log.debug("proceed", "continuing the following operations")
				continue
			}

			config.log.debug("proceed", "proceeded port #$l $port_pair of profile #$i '$name' successfully")
		}
	}

	return error_count
}

fn list_profiles(config &ConfigData) {
	config.log.debug("list", "logging currently loaded config: $config")

	config.log.println("Now logging the loaded profiles:")
	config.log.println("Tasklisted profiles: ${join_array(config.run_addresses)}")

	for profile, value in config.addresses {
		mut ports_str := ""
		if value.ports.len == 0 {
			ports_str = "[none]"
		} else {
			ports_str = value.str_port(0)

			for portidx, _ in value.ports[1..] {
				ports_str += ", " + value.str_port(portidx + 1)
			}
		}
		config.log.println("Profile '$profile': address '$value.address'; origin '$value.origin'; ports $ports_str")
	}
}

fn main() {
	mut config := ConfigData {}

	if "--debug" in os.args[1..] {
		config.log.level = .debug
		config.log.debug("args", "loglevel: debug")
	} else if "--verbose" in os.args[1..] {
		config.log.level = .info
	} else if "--quiet" in os.args[1..] || "--no-warn" in os.args[1..] {
		config.log.level = .error
	} else if "--silent" in os.args[1..] {
		config.log.level = .silent
	}

	config.log.debug("main", "starting decoding main config")
	config = get_config(mut &config, "main.conf") or {
		config.log.debug("main", "config returned an error; aborting")
		return
	}
	config.log.debug("main", "ended decoding main config")

	config.log.debug("main", "starting decoding arguments")
	config = get_args(mut &config) or {
		config.log.debug("main", "args returned an error; aborting")
		return
	}
	config.log.debug("main", "ended decoding arguments")

	config.log.debug("main", "logging currently loaded config: $config")

	match config.proceed {
		.proceed {
			if config.run_addresses.len == 0 {
				config.log.info("main", "the address list is empty! exiting...")
				return
			}

			config.log.debug("main", "starting proceeding")
			error_count := proceed(&config) or {
				config.log.debug("main", "proceed returned an error")
				-1
			}
			config.log.debug("main", "ended proceeding")

			if error_count > 0 {
				config.log.warn("main", "$error_count errors occured during execution, some tunnels may not be set")
			} else {
				config.log.info("main", "everything went fine!")
			}
		}
		.list {
			list_profiles(&config)
		}
		.list_all {
			config.log.debug("list-all", "getting a list of the config files")

			config_xdg := os.config_dir() or {
				config.log.error("list-all", "unable to find the global configuration directory")
				return
			}
			config_dir := os.join_path_single(config_xdg, "sshtpt")
			if ! os.is_dir(config_dir) {
				config.log.error("list-all", "unable to find the sshtpt configuration directory (${config_dir})")
				return
			}
			config_files := os.ls(config_dir) or {
				config.log.error("list-all", "unable to read the global configuration directory")
				return
			}

			config.log.debug("list-all", "reading each config files")
			mut errornb := 0
			for file in config_files {
				get_config(mut &config, file) or {
					config.log.debug("list-all", "config returned an error; continuing with the next configs")
					errornb++
					continue
				}
			}

			if errornb != 0 {
				config.log.warn("list-all", "at least one configuration file could not be loaded")
			}

			list_profiles(&config)
		}
		.end {
			config.log.debug("main", "found 'no proceed' in config, exiting now...")
		}
	}

	config.log.debug("main", "main ended")
}
