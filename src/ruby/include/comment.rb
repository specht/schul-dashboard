class Main < Sinatra::Base
    def delete_audio_comment(tag)
        require_teacher!
        if tag && tag.class == String && tag =~ /^[0-9a-zA-Z]+$/
            dir = tag[0, 2]
            filename = tag[2, tag.size - 2]
            ['.ogg', '.mp3'].each do |ext|
                path = "/raw/uploads/audio_comment/#{dir}/#{filename}#{ext}"
                if File.exist?(path)
                    STDERR.puts "DELETING #{path}"
                    FileUtils::rm_f(path)
                end
            end
        end
    end
    
    post '/api/upload_audio_comment' do
        require_teacher!
        lesson_key = params['lesson_key']
        schueler = params['schueler']
        lesson_offset = params['lesson_offset'].to_i
        duration = params['duration'].to_i
        entry = params['file']
        blob = entry['tempfile'].read
        tag = RandomTag.to_base31(('f' + Digest::SHA1.hexdigest(blob)).to_i(16))[0, 16]
        id = RandomTag.generate(12)
        FileUtils.mkpath("/raw/uploads/audio_comment/#{tag[0, 2]}")
        temp_target_path = "/raw/uploads/audio_comment/#{tag[0, 2]}/#{tag[2, tag.size - 2]}.temp.mp3"
        FileUtils::mv(entry['tempfile'].path, temp_target_path)
        FileUtils::chmod('a+r', temp_target_path)
        target_path = "/raw/uploads/audio_comment/#{tag[0, 2]}/#{tag[2, tag.size - 2]}.mp3"
        system("ffmpeg -i \"#{temp_target_path}\" \"#{target_path}\"")
        FileUtils::chmod('a+r', target_path)
        old_tag = nil
        transaction do
            timestamp = Time.now.to_i
            results = neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :key => lesson_key, :offset => lesson_offset, :schueler => schueler, :audio_comment_tag => tag, :duration => duration, :timestamp => timestamp, :id => id)
                MATCH (u:User {email: $schueler})
                MERGE (l:Lesson {key: $key})
                MERGE (u)<-[ruc:TO]-(c:AudioComment {offset: $offset})-[:BELONGS_TO]->(l)
                WITH ruc, u, c, c.tag as old_tag
                SET c.id = $id
                SET c.tag = $audio_comment_tag
                SET c.duration = $duration
                SET c.updated = $timestamp
                REMOVE ruc.seen
                WITH c, old_tag
                OPTIONAL MATCH (c)-[r:FROM]->(:User)
                DELETE r
                WITH c, old_tag
                MATCH (su:User {email: $session_email})
                MERGE (c)-[:FROM]->(su)
                RETURN old_tag
            END_OF_QUERY
            old_tag = (results.first || {})['old_tag']
        end
        # also delete ogg file on disk
        delete_audio_comment(old_tag)
        trigger_update("#{lesson_key}/wait")
        respond(:tag => tag)
    end
    
    post '/api/delete_audio_comment' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :schueler, :lesson_offset],
                                  :types => {:lesson_offset => Integer})
        old_tag = nil
        transaction do 
            timestamp = Time.now.to_i
            results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => data[:lesson_offset], :schueler => data[:schueler], :timestamp => timestamp)
                MATCH (:User {email: $schueler})<-[:TO]-(c:AudioComment {offset: $offset})-[:BELONGS_TO]->(:Lesson {key: $key})
                WITH c, c.tag AS old_tag
                SET c = {offset: c.offset, updated: $timestamp}
                WITH c, old_tag
                OPTIONAL MATCH (c)-[r:FROM]->(:User)
                DELETE r
                RETURN old_tag
            END_OF_QUERY
            old_tag = results.first['old_tag']
        end
        # also delete ogg file on disk
        delete_audio_comment(old_tag)
        trigger_update("#{data[:lesson_key]}/wait")
        respond(:ok => true)
    end
    
    post '/api/publish_text_comment' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :schueler, :lesson_offset, :comment],
                                  :max_body_length => 4096,
                                  :max_string_length => 4096,
                                  :types => {:lesson_offset => Integer})
        id = RandomTag.generate(12)
        transaction do 
            timestamp = Time.now.to_i
            neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :key => data[:lesson_key], :offset => data[:lesson_offset], :schueler => data[:schueler], :text_comment => data[:comment], :timestamp => timestamp, :id => id)
                MATCH (u:User {email: $schueler})
                MERGE (l:Lesson {key: $key})
                MERGE (u)<-[ruc:TO]-(c:TextComment {offset: $offset})-[:BELONGS_TO]->(l)
                SET c.comment = $text_comment
                SET c.created = $timestamp
                SET c.updated = $timestamp
                SET c.id = $id
                REMOVE ruc.seen
                WITH c
                OPTIONAL MATCH (c)-[r:FROM]->(:User)
                DELETE r
                WITH c
                MATCH (su:User {email: $session_email})
                MERGE (c)-[:FROM]->(su);
            END_OF_QUERY
        end
        trigger_update("#{data[:lesson_key]}/wait")
        respond(:ok => true)
    end
    
    post '/api/delete_text_comment' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :schueler, :lesson_offset],
                                  :types => {:lesson_offset => Integer})
        transaction do 
            timestamp = Time.now.to_i
            results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => data[:lesson_offset], :schueler => data[:schueler], :timestamp => timestamp)
                MATCH (u:User {email: $schueler})<-[:TO]-(c:TextComment {offset: $offset})-[:BELONGS_TO]->(l:Lesson {key: $key})
                SET c = {offset: c.offset, updated: $timestamp}
                WITH c
                OPTIONAL MATCH (c)-[r:FROM]->(:User)
                DELETE r
            END_OF_QUERY
        end
        trigger_update("#{data[:lesson_key]}/wait")
        respond(:ok => true)
    end
end
