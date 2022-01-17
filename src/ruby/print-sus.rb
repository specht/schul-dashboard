#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require 'digest/sha2'
require 'yaml'

class Script
    def run
        parser = Parser.new()
        entries = []

        parser.parse_schueler do |record|
            entries << {:email => record[:email],
                        :display_name => record[:display_name],
                        :display_first_name => record[:display_first_name],
                        :last_name => record[:last_name],
                        :display_last_name => record[:display_last_name],
                        :klasse => record[:klasse]
                       }
        end
        @@klassen_order = Main.class_variable_get(:@@klassen_order)
        entries.sort do |a, b|
            (a[:klasse] == b[:klasse]) ?
            (a[:last_name] <=> b[:last_name]) :
            ((@@klassen_order.index(a[:klasse]) || -1) <=> (@@klassen_order.index(b[:klasse]) || -1))
        end.each do |record|
            STDERR.puts "[#{record[:klasse]}] #{record[:display_name]} <#{record[:email]}>"
        end
    end
end

script = Script.new
script.run
