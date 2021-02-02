#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require 'zlib'

class Script
    include QtsNeo4j
    
    def run
        @@user_info = Main.class_variable_get(:@@user_info)
        @@klassen_for_shorthand = Main.class_variable_get(:@@klassen_for_shorthand)
        @@klassen_order = Main.class_variable_get(:@@klassen_order)
        @@schueler_for_klasse = Main.class_variable_get(:@@schueler_for_klasse)
        @@predefined_external_users = Main.class_variable_get(:@@predefined_external_users)
        parser = Parser.new()
        transaction do
            # give admin rights to admin
            ADMIN_USERS.each do |email|
                neo4j_query(<<~END_OF_QUERY, :email => email)
                    MATCH (u:User {email: {email}})
                    SET u.admin = true;
                END_OF_QUERY
            end
        end        
        transaction do
            parser.parse_lehrer do |record|
                neo4j_query(<<~END_OF_QUERY, :email => record[:email])
                    MERGE (u:User {email: {email}})
                END_OF_QUERY
            end
        end
        transaction do
            parser.parse_schueler do |record|
                neo4j_query(<<~END_OF_QUERY, :email => record[:email])
                    MERGE (u:User {email: {email}})
                END_OF_QUERY
            end
        end
        transaction do
            neo4j_query(<<~END_OF_QUERY, :email => "lehrer.tablet@#{SCHUL_MAIL_DOMAIN}")
                MERGE (u:User {email: {email}})
            END_OF_QUERY
            neo4j_query(<<~END_OF_QUERY, :email => "kurs.tablet@#{SCHUL_MAIL_DOMAIN}")
                MERGE (u:User {email: {email}})
            END_OF_QUERY
        end
        transaction do
            @@predefined_external_users[:recipients].each_pair do |k, v|
                next if v[:entries]
                neo4j_query(<<~END_OF_QUERY, :email => k, :name => v[:label])
                    MERGE (n:PredefinedExternalUser {email: {email}, name: {name}})
                END_OF_QUERY
            end
        end
    end
end

script = Script.new
script.run
