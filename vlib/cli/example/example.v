module main

import os
import cli

fn main() {
	mut app := cli.Command{
		name: 'example-app'
		description: 'example-app'
		execute: fn (cmd cli.Command) ? {
			println('hello app')
			return
		}
		commands: [
			cli.Command{
				name: 'sub'
				execute: fn (cmd cli.Command) ? {
					println('hello subcommand')
					return
				}
				disable_help: false
			},
		]
		flags: [
			cli.Flag{
				flag: cli.FlagType.bool
				name: 'hello'
				global: true
			}
		]
	}
	app.setup()
	app.parse(os.args)
}