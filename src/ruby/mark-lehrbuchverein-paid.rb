#!/usr/bin/env ruby
require './main.rb'
require 'neo4j_bolt'

class Script
    def initialize
    end
    
    def run
        srsly = false
        if ARGV.include?('--srsly')
            srsly = true
        else
            STDERR.puts "Notice: Not making any modifications unless you specify --srsly"
        end
        @@user_info = Main.class_variable_get(:@@user_info)
        @@users_for_role = Main.class_variable_get(:@@users_for_role)
        @@schueler_for_klasse = Main.class_variable_get(:@@schueler_for_klasse)
        KLASSEN_ORDER.each do |klasse|
            next if klasse.to_i < 7
            @@schueler_for_klasse[klasse].each do |email|
                STDERR.puts "Marking paid: #{LEHRBUCHVEREIN_JAHR} #{email}"
                if srsly
                    $neo4j.neo4j_query(<<~END_OF_QUERY, {:email => email, :jahr => LEHRBUCHVEREIN_JAHR})
                        MATCH (u:User {email: $email})
                        MERGE (j:Lehrbuchvereinsjahr {jahr: $jahr})
                        CREATE (u)-[:PAID_FOR]->(j)
                        RETURN u.lehrbuchverein_mitglied;
                    END_OF_QUERY
                end
            end
        end
    end
end

script = Script.new
script.run
