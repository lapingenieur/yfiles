module main
import os

struct ParseArgsSt {
	array []string
pub mut:
	idx int
}
fn (mut self ParseArgsSt) next() ?string {
	if self.idx >= self.array.len {
		return none
	}
	defer { self.idx += 1 }
	return self.array[self.idx]
}
fn (self ParseArgsSt) get() string {
	return self.array[self.idx]
}

fn help() {
	println("tunnel - create a port-forwarding tunnel with SSH
usage:
  tunnel [ARG...] [PORT...]
description:
  creates a reverse ssh tunnel that forwards distant TCP port #N to local TCP port #N
arguments:
  -h, --help
	print this help
  -a IP, --address IP
	specify the distant IPv4 to connect")
}

struct ArgEnd {}
struct ArgData {
	addresses map[string][]u64
}
type ArgResult = ArgEnd | ArgData

fn get_args() !ArgResult {
	mut addresses := { 'default': []u64{cap: 10} }
	mut address := "default"

	mut args := ParseArgsSt {
		array: os.args[1..]
		idx: 0
	}
	for {
		arg := args.next() or {
			break
		}

        match arg {
            "--help", "-h" {
					help()
					return ArgEnd {}
				}
			"--address", "-a" {
				param := args.next() or {
					return error("Error: lacking parameter for arguments '${arg}'")
				}

				splitted := param.split(".")
				if splitted.len == 4 {
					for chunk in splitted {
						chunk.parse_uint(10, 8) or {
							return error("Error: invalid ip specified '${param}'")
						}
					}
				} else {
					return error("Error: invalid ip specified '${param}'")
				}

				address = param
				if _ := addresses[param] {
					continue
				}
				addresses[param] = []u64{cap: 5}
			}
			else {
					port := arg.parse_uint(10, 64) or {
						return error("Error: unknown argument '${arg}'")
					}
					addresses[address] << port
				}
        }
	}

	return ArgData { addresses: addresses }
}

fn get_config() !map[string][]string {
	template := map[string][]string
	config_dir := os.config_dir() or {
		return error("config/error: unable to find the configuration directory")
	}
	config_path := os.join_path_single(config_dir, "sshtpt.conf")

	if os.is_file(config_path) {
		config_lines := os.read_lines(config_path)
		///// i was here !!!
		for i, line in config_lines {
			if (line.contains(":")) {
				directive, value := line.split_once(line)
				match directive {
					"default_address" {
						config_dir["default_address"] = value.trim(" ")
					}
					else {
						return error("config/error: unknown config directive '${directive}' at line ${i} of sshtpt.conf")
					}
				}
			}
		}
	} else {
		return error("config/error: unable to find the configuration file '[config_dir]/sshtpt.toml'")
	}
}

fn main() {
	status := get_args() or {
		eprintln(err)
		return
	}

	config := get_config() or {
		eprintln(err)
		return
	}

	match status {
		ArgEnd { return }
		ArgData { }
	}

	println(status.addresses)
	user := "username"

//	for ip, ports in config {
//		for port in ports {
//			os.execute("echo ssh -fNR ${port}:localhost:${port} ${user}@${ip} >> /home/lapingenieur/helloworld.text")
//		}
//	}
}
