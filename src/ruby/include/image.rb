class Main < Sinatra::Base
    post '/api/upload_image' do
        require_user_who_can_upload_files!
        slug = params['slug']
        slug.strip!
        assert(slug =~ /^[a-zA-Z0-9\-_]+$/)
        assert(!slug.include?('.'))
        assert(slug.size > 0)
        entry = params['file']
        filename = entry['filename']
        blob = entry['tempfile'].read
        path = "/raw/uploads/images/#{slug}.#{filename.split('.').last}"
        File.open(path, 'w') do |f|
            f.write(blob)
        end
        trigger_update_images()
        respond(:uploaded => 'yeah')
    end    
    
    post '/api/delete_image' do
        require_user_who_can_upload_files!
        data = parse_request_data(:required_keys => [:slug])
        slug = data[:slug]
        slug.strip!
        assert(slug =~ /^[a-zA-Z0-9\-_]+$/)
        assert(!slug.include?('.'))
        assert(slug.size > 0)
        Dir["/raw/uploads/images/#{slug}.*"].each do |path|
            STDERR.puts "Deleting #{path}"
            FileUtils::rm_f(path)
            local_slug = File.basename(path).split('.').first
            (GEN_IMAGE_WIDTHS.reverse + [:p]).each do |width|
                Dir["/gen/i/#{local_slug}-#{width}.*"].each do |sub_path|
                    STDERR.puts "Deleting #{sub_path}"
                    FileUtils::rm_f(sub_path)
                end
            end
        end
        respond(:deleted => 'yeah')
    end    
    
    post '/api/get_all_images' do
        require_user_who_can_upload_files!
        images = []
        Dir['/raw/uploads/images/*'].each do |path|
            images << {
                :slug => File.basename(path).split('.').first,
                :size => File.size(path),
                :timestamp => File.mtime(path)
            }
        end
        images.sort! { |a, b| b[:timestamp] <=> a[:timestamp] }
        respond(:images => images)
    end    
end
