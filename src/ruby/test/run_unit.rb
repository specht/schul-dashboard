# Runs all unit tests. Inside the test stack: ./test.sh unit
# (or, in a container with /app = src/ruby: ruby test/run_unit.rb)

require 'date'
Dir[File.join(__dir__, 'unit', '**', '*_test.rb')].sort.each { |f| require f }
