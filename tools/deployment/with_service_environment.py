#!/usr/bin/env python3
"""Run a deployment command with a running service's environment, without printing it."""

import argparse
import os
import re
import shlex


def read_environment_file(path):
    environment = {}
    with open(path, encoding="utf-8") as source:
        for number, line in enumerate(source, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                tokens = shlex.split(line, comments=False, posix=True)
            except ValueError:
                raise SystemExit("Unsupported quoting in environment file at line " + str(number))
            if len(tokens) != 1 or "=" not in tokens[0]:
                raise SystemExit("Unsupported environment assignment at line " + str(number))
            key, value = tokens[0].split("=", 1)
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
                raise SystemExit("Invalid environment variable name at line " + str(number))
            environment[key] = value
    return environment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment-file", action="append", default=[])
    parser.add_argument("pid", type=int)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    if not arguments.command or arguments.pid <= 0:
        parser.error("A positive PID and command are required.")
    process_directory = "/proc/" + str(arguments.pid)
    if os.stat(process_directory).st_uid != os.getuid():
        raise SystemExit("The service process must belong to the current deployment user.")
    with open(process_directory + "/environ", "rb") as environment_file:
        entries = environment_file.read().split(b"\0")
    environment = os.environ.copy()
    for entry in entries:
        if b"=" in entry:
            key, value = entry.split(b"=", 1)
            environment[os.fsdecode(key)] = os.fsdecode(value)
    # Ruby/Puma process-title changes may erase its original /proc environment.
    # Read the unit's explicit EnvironmentFile without shell evaluation or logging.
    for path in arguments.environment_file:
        environment.update(read_environment_file(path))
    environment["RAILS_ENV"] = "production"
    os.execvpe(arguments.command[0], arguments.command, environment)


if __name__ == "__main__":
    main()
