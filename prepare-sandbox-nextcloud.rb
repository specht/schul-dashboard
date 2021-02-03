#!/usr/bin/env ruby

require 'stringio'

STDERR.puts "Installing user_external app in Sandbox Nextcloud..."
system("./config.rb run nextcloud php occ app:install user_external")

STDERR.puts "Activating HTTP Basic Authentication Fallback for Sandbox Nextcloud..."
config = StringIO.open do |io|
    File.open('data/nextcloud/config/config.php') do |f|
        f.each_line do |line|
            if line.include?('OC_User_BasicAuth')
                STDERR.puts "OC_User_BasicAuth already present in config, exiting..."
                exit(1)
            end
            if line.strip == ');'
                io.puts "  'user_backends' => array("
                io.puts "      array("
                io.puts "          'class' => 'OC_User_BasicAuth',"
                io.puts "          'arguments' => array('http://nginx/nc_auth'),"
                io.puts "      ),"
                io.puts "  ),"
            end
            io.puts line
        end
    end
    io.string
end

File.open('data/nextcloud/config/config.php', 'w') do |f|
    f.write(config)
end
