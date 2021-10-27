#!/usr/bin/ruby
# frozen_string_literal: true

require 'r80'

if ARGV.empty?
  puts 'Usage: rz80 <z80 binary> [<max_steps>]'
  exit
end

# An optional step limit is handy for profiling
limit = 0
limit = ARGV[1].to_i if ARGV.size > 1

# Initialise the simulated system
sys = R80::System.new(0x10000, 0x0100)

# Load the specified binary into memory starting at 0x0100
sys.load_binary(0x0100, ARGV[0])

# Run the binary until a termination condition is encountered
# or the (optional) step limit is reached.
steps = 1
while sys.running
  steps += 1
  break if steps == limit

  sys.execute_instruction
end
puts "#steps = #{steps}"
