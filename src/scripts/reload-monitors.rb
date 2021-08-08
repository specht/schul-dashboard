#!/usr/bin/env ruby

# TODO: This is not functional yet. Add a way to prevent spamming from the outside
system("cd ../.. && ./config.rb exec ruby curl http://localhost:3000/api/force_reload_monitors && cd src/scripts")
