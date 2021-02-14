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
        # send event invites
        rows = @@neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| {:eid => x['eid'], :email => x['email'], :name => x['name'], :org_email => x['org_email'] } }
            MATCH (u)-[rt:IS_PARTICIPANT]->(e:Event)-[:ORGANIZED_BY]->(ou:User)
            WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND rt.invitation_requested = true AND COALESCE(rt.deleted, false) = false AND COALESCE(e.deleted, false) = false
            RETURN e.id AS eid, u.email AS email, u.name AS name, ou.email AS org_email
        END_OF_QUERY

        if rows.size > 0
            STDERR.puts ">>> Sending #{rows.size} event invites!"
            STDERR.puts '-' * 59
            rows.each.with_index do |row, i|
                # send invitation mail
                STDERR.puts ">>> Sending invite #{i + 1} of #{rows.size}..."
                STDERR.puts '-' * 59
                Main.invite_external_user_for_event(row[:eid], row[:email], row[:org_email])
                sleep 10.0
                # wait for 10 seconds
            end
        end
        
        # send poll run invites
        rows = @@neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| {:prid => x['prid'], :email => x['email'], :name => x['name'], :org_email => x['org_email'] } }
            MATCH (u)-[rt:IS_PARTICIPANT]->(pr:PollRun)-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(ou:User)
            WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND rt.invitation_requested = true AND COALESCE(rt.deleted, false) = false AND COALESCE(pr.deleted, false) = false AND COALESCE(p.deleted, false) = false
            RETURN pr.id AS prid, u.email AS email, u.name AS name, ou.email AS org_email
        END_OF_QUERY

        if rows.size > 0
            STDERR.puts ">>> Sending #{rows.size} poll run invites!"
            STDERR.puts '-' * 59
            rows.each.with_index do |row, i|
                # send invitation mail
                STDERR.puts ">>> Sending invite #{i + 1} of #{rows.size}..."
                STDERR.puts '-' * 59
                Main.invite_external_user_for_poll_run(row[:prid], row[:email], row[:org_email])
                sleep 10.0
                # wait for 10 seconds
            end
        end
    end
    
    configure do
        @@neo4j = Neo4jHelper.new()
        @@neo4j.wait_for_neo4j()
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
