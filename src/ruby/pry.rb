#!/usr/bin/env ruby
require 'pry'
require './main.rb'

class Main < Sinatra::Base
    def hello
        puts 'hello, world!'
    end
end

Main.new
