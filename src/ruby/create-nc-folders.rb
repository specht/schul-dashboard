#!/usr/bin/env ruby
require './main.rb'

ALSO_CREATE_OS_FOLDERS = false

class Script
    def emit(s)
        puts "__RUN__ #{s}"
    end
    
    def exit_if_not_exists(path)
        emit "if [ ! -d \"#{path}\" ]"
        emit "then"
        emit "    echo \"Path does not exist: #{path}\""
        emit "    exit 1"
        emit "fi"
    end
    
    def run
        emit "#!/bin/bash"
        base_path = File.join(NEXTCLOUD_DASHBOARD_DATA_DIRECTORY, 'files')
        exit_if_not_exists(base_path)
        @@user_info = Main.class_variable_get(:@@user_info)
        @@faecher = Main.class_variable_get(:@@faecher)
        @@klassen_order = Main.class_variable_get(:@@klassen_order)
        @@lessons_for_klasse = Main.class_variable_get(:@@lessons_for_klasse)
        @@lessons = Main.class_variable_get(:@@lessons)
        @@schueler_for_klasse = Main.class_variable_get(:@@schueler_for_klasse)
        @@schueler_for_lesson = Main.class_variable_get(:@@schueler_for_lesson)
        @@lessons[:lesson_keys].keys.sort.each do |lesson_key|
            lesson_info = @@lessons[:lesson_keys][lesson_key]
            next if (Set.new(lesson_info[:klassen]) & Set.new(@@klassen_order)).empty?
            unless ALSO_CREATE_OS_FOLDERS
                next unless (Set.new(lesson_info[:klassen]) & Set.new(['11', '12'])).empty?
            end
            folder_name = "#{lesson_key}"
            einsammel_path = "Auto-Einsammelordner (von SuS an mich)"
            rueckgabe_path = "Auto-Rückgabeordner (von mir an SuS)"
            STDERR.puts sprintf('%3d %-20s %-10s %s', (@@schueler_for_lesson[lesson_key] || []).size, lesson_key, lesson_info[:lehrer].join(', '), lesson_info[:klassen].join(', '))
            ['Ausgabeordner', einsammel_path, rueckgabe_path].each do |x|
                emit "mkdir -pv \"#{File.join(base_path, 'Unterricht', folder_name, x)}\""
            end
            (@@schueler_for_lesson[lesson_key] || []).each do |email|
                name = @@user_info[email][:display_name]
                ['Einsammelordner', 'Einsammelordner/Eingesammelt', 'Rückgabeordner'].each do |x|
                    emit "mkdir -pv \"#{File.join(base_path, 'Unterricht', folder_name, 'SuS', name, x)}\""
                end
            end
        end
        emit "php occ files:scan #{File::basename(NEXTCLOUD_DASHBOARD_DATA_DIRECTORY)}"
        emit "# Hinweis: Die oben stehenden Befehle wurden noch nicht ausgeführt."
        emit "# Falls die Nextcloud z. B. in einem Docker-Container läuft, können sie"
        emit "# z. B. so ausgeführt werden:"
        emit "# $ ./#{File.basename(__FILE__)} | docker exec -i schuldashboarddev_nextcloud_1 bash -"
    end
end

script = Script.new
script.run
