module main

import term
import term.termios
import os
import time

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
	password_mode PasswordMode
	ports []u64 = []u64{cap: 5}
}
fn (mut self AddressData) add_port(port u64) {
	self.ports << port
}

//// ConfigData
struct ConfigData {
pub mut:
	addresses map[string]AddressData = map[string]AddressData
	run_addresses []string
	proceed bool = true
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

fn help() {
	println("sshtpt - SSH TCP-Port Tunnel (v1.0)

usage:
  tunnel [ARG...]
description:
  creates a reverse ssh tunnel that forwards distant TCP port #N to local TCP port #N

general arguments:
  -h, --help
	print this help

tunneling arguments:
  -a, --address HOSTNAME PORT...
	specify the distant HOSTNAME to connect (either IPv4 or url)
	and the list of PORT-s to forward
  --add PROFILE...
	specify profiles found in the configuration to use for tunneling (see configuration)
  --use CONFIG...
	specify config files that live in the configuration directory to read and include
	user can indicate profiles in different config files and load them lazily,
	so sshtpt doesn't spend too much time reading the main configuration
the following arguments need to be preceeded by an occurence of -a HOSTNAME
this HOSTNAME is below referenced to as the 'current profile'
note that very similar instructions exist for sshtpt config files, see configuration
  --password PASSWORD
	warning! you really shouldn't use this particular argument as PASSWORD is exposed system-wide
    specify the password to use for the current profile
  --empty-password, --password-empty
	warning! you shouldn't use this argument as it exposes password-related data system-wide
	indicate that the password for the current profile should be an empty string
  --ask-password, --password-ask
	indicate that the password for the current profile should be asked to the user when needed,
	even if the profile's configuration gives another method
	note: this is the default mode when adding addresses from the CLI
  --env-password, --password-env ENV
	load the password for the current profile from the ENV environment variable
  --password-location FILE
	indicate that the password for the current profile should be read from the file FILE,
	given either as an absolute path, or a path relative to ~/.sshtpt/ or \$XDG_CONFIG/sshtpt/

logging arguments:
  --silent
	very silent output, only ssh* subcommands can potentially print to stdout and stderr
  --quiet, --no-warn
	only print error messages
  --verbose
	be verbosive, print secondary information
  --debug
	be very-verbosive, print debugging information

configuration:
  the main config file is XDG_CONFIG/sshtpt/main.conf, where XDG_CONFIG stands for the user configuration directory;
  it is read at each execution of sshtpt, therefore it should not contain too many things to interprete;
  other files with `.conf` extention can stay in this directory and can be interpreted if the user explicitely
  indicates in the CLI arguments or with the include-config instructions

config file syntax:
  a man-like description would be: ( INS [: ARG...] ; )...
  - a declaration consists of an instruction (INS) with or without arguments (ARG...)
  - instructions are separated from their potential arguments by a colon (:)
  - a declaration must end with a semi colon (;), it is placed right after the instruction if there's no argument
  - the arguments are separated by any of the space-like character (space, \\n, \\t, \\v, \\f and \\r)
  - one argument shall not contain any space-like character
  - a declaration can span several lines as long as they respect the upper needs
  !! be aware that sshtpt will return an error if one of the specified config files contain errors
list of config declarations:
  address,
  profile: ADDRESS [ARG [PARAM]...]...
    define a new address profile with address ADDRESS (name will be set to ADDRESS as well)
    arguments:
      ports, port PORT...
        append a PORT to the list of ports
      name NAME
        set the profile name to NAME
    plus all the CLI arguments explained below the 'preceeded by -a' section, without the double dash prefixes
  include: FILE
    also read the file FILE, located in either directory explained under the 'configuration' section")
}

//// ArgDecodeModes used as buffer
enum ArgDecodeModes {
	zero
	ports
	use
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
					help()
					config.proceed = false
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
				config.addresses[param] = AddressData { address: address }
				config.run_addresses << address
				mode = .ports
			}
			"--add" {
				mode = .use
			}
			"--password" {
				param := args.next() or {
					config.log.error("args", "missing parameter for argument ${args.idx} '${arg}'")
					return error("")
				}

				config.log.warn("args", "you shouldn't indicate your passwords in the commandline")
				config.log.warn("args", "=> prefer defining them in special config files (see help/config) or using --ask-password argument")

				config.addresses[address].password = param
			}
			"--empty-password", "--password-empty" {
				config.addresses[address].password_mode = .empty
			}
			"--ask-password", "--password-ask" {
				config.addresses[address].password_mode = .ask
			}
			"--env-password", "--password-env" {
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
						port := arg.parse_uint(10, 64) or {
							config.log.error("args", "unknown argument '${arg}'")
							return error("")
						}

						config.addresses[address].add_port(port)
					}
					.use {
						config.run_addresses << arg
					}
					.zero {
							config.log.error("args", "unknown argument '${arg}'")
							return error("")
					}
				}
			}
        }
	}

	return config
}

fn get_config(mut config &ConfigData) !ConfigData {
	config_xdg := os.config_dir() or {
		config.log.error("config", "unable to find the global configuration directory")
		return error("")
	}
	config_dir := os.join_path_single(config_xdg, "sshtpt")
	if ! os.is_dir(config_dir) {
		config.log.error("config", "unable to find the sshtpt configuration directory (${config_dir})")
		return error("")
	}
	config_main := os.join_path_single(config_dir, "main.conf")
	if ! os.is_file(config_main) {
		config.log.error("config", "unable to find the main configuration file (${config_main})")
		return error("")
	}

	config_instructions := (os.read_file(config_main) or {
		config.log.error("config", "unable to read the main config file")
		return error("")
	}).split(";")
	for i, instruction in config_instructions {
		if instruction.contains(":") {
			mut directive, mut value := instruction.split_once(":")
			directive = directive.trim_space()
			value = value.trim_space()

			match directive {
				"" { continue }
				"address", "profile" {
					mut args := ParseArgsSt {
						array: value.split_any(" \t\v\f\r\n")
						idx: 1
					}
					mut name := args.array[0]
					mut address_template := AddressData { address: name }

					mut mode_port := false
					for {
						arg := args.next() or {
							break
						}

						match arg {
							"ports", "port" { mode_port = true }
							"name" {
								name = args.next() or {
									config.log.error("args", "missing name arguments at instruction ${i} '${instruction}' of main.conf")
									return error("")
								}
							}
							"password-location" {
								mut location := args.next() or {
									config.log.error("args", "missing password-location argument at instruction ${i} '${instruction}' of main.conf")
									return error("")
								}

								if os.is_file(os.join_path(os.home_dir(), ".sshtpt", location)) {
									location = os.join_path(os.home_dir(), ".sshtpt", location)
								} else if os.is_file(os.join_path(config_dir, location)) {
									location = os.join_path(config_dir, location)
									config.log.warn("config", "password files shouldn't stay in the configuration directory for security reasons")
								} else if ! os.is_file(location) {
									config.log.error("config", "unexisting file '${location}' specified by password-location at instruction ${i} of main.conf")
									return error("")
								}

								password := (os.read_file(location) or {
									config.log.error("config", "failed reading from password-location file '${location}' at instruction ${i} of main.conf: ${err}")
									return error("")
								}).trim("\n")
								if password.count("\n") != 0 {
									config.log.error("config", "password in file ${location} must be single-instruction at instruction ${i} of main.conf")
									return error("")
								}
								address_template.password = password
							}
							"password-env", "env-password" {
								param := args.next() or {
									config.log.error("config", "missing password-env argument at instruction ${i} of main.conf")
									return error("")
								}
								password := os.getenv_opt(param) or {
									config.log.error("config", "the environment variable '${name}' specified for password-env is currently undeclared at instruction ${i} of main.conf")
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
							"password" {
								address_template.password = args.next() or {
									config.log.error("config", "missing password argument at instruction ${i} '${instruction}' of main.conf")
									return error("")
								}
							}
							else {
								if port := arg.parse_uint(10, 64) {
									if mode_port {
										address_template.add_port(port)
									} else {
										config.log.error("config", "expected argument 'ports' before any ports specified at instruction ${i} of main.conf")
										return error("")
									}
								} else {
									config.log.error("config", "unknown argument '${arg}' at instruction ${i} of main.conf")
									return error("")
								}
							}
						}
					}

					config.addresses[name] = address_template
				}
				else {
					config.log.error("config", "unknown config directive '${directive}' at instruction ${i} of main.conf")
					return error("")
				}
			}
		}
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
					log.debug("exec", "child returned with status $status")
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

fn proceed(config &ConfigData) ! {
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

	for i, name in config.run_addresses {
		config.log.debug("proceed", "proceeding profile #$i '$name'")

		if name !in config.addresses {
			config.log.error("proceed", "$name is not a configured address profile")
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
		} else {
			password = input_hidden("Password for profile '$name': ") or {
				config.log.error("proceed", "failed reading password for profile #$i '$name'")
				config.log.debug("proceed", "continuing with the next profile")
				continue
			}
		}

		plusenv := ["SSHPASS=$password"]
		// important !!! index -2 below should be always empty because port-forwarding gets put there
		mut args := ["-e", "ssh", "-oConnectTimeout=4", "-fNR", "", profile.address]

		for l, port in profile.ports {
			config.log.debug("proceed", "proceeding port #$l $port of profile #$i '$name'")

			args[args.len - 2] = "$port:localhost:$port"
			mut args_str := args[0]
			for each in args[1..] { args_str += " $each" }

			config.log.info("proceed", "command for port #$l $port of profile #$i '$name': `sshpass $args_str`")
			status := spawnvpec("sshpass", args, plusenv, config.log)
			if status != 0 {
				config.log.error("proceed", "failed tunnel creation for port #$l $port of profile #$i '$name' with status $status")
				config.log.debug("proceed", "continuing the following operations")
				continue
			}

			config.log.debug("proceed", "proceeded port #$l $port of profile #$i '$name' successfully")
		}
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

	config.log.debug("main", "starting decoding config")
	config = get_config(mut &config) or {
		config.log.debug("main", "config returned an error; aborting")
		return
	}
	config.log.debug("main", "decoding config ended")

	config.log.debug("main", "starting decoding arguments")
	config = get_args(mut &config) or {
		config.log.debug("main", "args returned an error; aborting")
		return
	}
	config.log.debug("main", "decoding arguments ended")

	config.log.debug("main", "logging loaded config: $config")

	if config.proceed {
		if config.run_addresses.len == 0 {
			config.log.info("main", "the address list is empty! exiting...")
			return
		}

		config.log.debug("main", "starting proceeding")
		proceed(&config) or {
			config.log.debug("main", "proceed returned an error")
		}
		config.log.debug("main", "proceeding ended")
		config.log.info("main", "everything went fine!")
	} else {
		config.log.debug("main", "got no proceed, exiting now...")
	}

	config.log.debug("main", "main ended")
}
