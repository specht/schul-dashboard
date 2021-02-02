#!/usr/bin/env ruby
require './main.rb'
require 'json'
require 'zlib'
require 'fileutils'
require 'thread'

class Neo4jHelper
    include QtsNeo4j
end

class InvitationRepl < Sinatra::Base
    
    configure do
        set :show_exceptions, false
    end
    
    def self.perform_update(which)
        STDERR.puts ">>> Sending invites!"
        STDERR.puts '-' * 59
        rows = @@neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| {:eid => x['eid'], :email => x['email'], :name => x['name'], :org_email => x['org_email'] } }
            MATCH (u)-[rt:IS_PARTICIPANT]->(e:Event)-[:ORGANIZED_BY]->(ou:User)
            WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND rt.invitation_requested = true AND COALESCE(rt.deleted, false) = false AND COALESCE(e.deleted, false) = false
            RETURN e.id AS eid, u.email AS email, u.name AS name, ou.email AS org_email
        END_OF_QUERY

        rows.each do |row|
            # send invitation mail
            Main.invite_external_user(row[:eid], row[:email], row[:org_email])
            sleep 10.0
            # wait for 10 seconds
        end
    end
    
    configure do
        @@neo4j = Neo4jHelper.new()
        begin
            if @@worker_thread
                Thread.kill(@@worker_thread)
            end
        rescue
        end
        @@queue = Queue.new
        @@worker_thread = Thread.new do
            while true do
                entry = @@queue.pop
                self.perform_update(entry[:which])
            end
        end
        self.perform_update(:all)
        STDERR.puts "REPL is ready."
    end
    
    get '/api/send_invites' do
        @@queue << {:which => :all}
    end

    run! if app_file == $0
end
