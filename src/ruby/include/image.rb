require 'digest'

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

    post '/api/upload_poll_image' do
        require_user!
        entry = params['file']
        filename = entry['filename']
        blob = entry['tempfile'].read
        sha1 = Digest::SHA1.hexdigest(blob)[0, 16]
        path = "/internal/poll_uploads/images/poll-#{sha1}.#{filename.split('.').last}"
        File.open(path, 'w') do |f|
            f.write(blob)
        end
        [2048].each do |width|
            jpg_path = "/internal/poll_uploads/images/poll-#{sha1}-#{width}.jpg"
            system("convert -auto-orient -set colorspace RGB  \"#{path}\" -resize #{width}x#{width}^ -quality 85 -sampling-factor 4:2:0 -strip \"#{jpg_path}\"")
        end
        FileUtils.rm_f(path)
        respond(:uploaded => 'yeah', :stored_path => "poll-#{sha1}")
    end

    get '/api/get_poll_photo/:slug' do
        require_user!
        slug = params[:slug]
        path = "/internal/poll_uploads/images/#{slug}"
        response.headers['Cache-Control'] = "max-age=#{3600 * 24 * 365}"
        respond_raw_with_mimetype(File.read(path), 'image/jpeg')
    end

    post '/api/upload_sus_image' do
        require_user!
        entry = params['file']
        filename = entry['filename']
        blob = entry['tempfile'].read
        sha1 = Digest::SHA1.hexdigest(blob)[0, 16]
        path = "/internal/sus_uploads/images/sus-#{sha1}.#{filename.split('.').last}"
        File.open(path, 'w') do |f|
            f.write(blob)
        end
        [512].each do |width|
            jpg_path = "/internal/sus_uploads/images/sus-#{sha1}-512.jpg"
            system("convert -auto-orient -set colorspace RGB  \"#{path}\" -resize #{width}x#{width}^ -quality 85 -sampling-factor 4:2:0 -strip \"#{jpg_path}\"")
        end
        FileUtils.rm_f(path)
        display_name = @session_user[:display_name]
        deliver_mail("New photo was uploaded by #{display_name} as sus-#{sha1}") do
            to WEBSITE_MAINTAINER_EMAIL
            bcc SMTP_FROM
            from SMTP_FROM

            subject "SuS Image Upload from #{display_name}"

            filename = "sus-#{sha1}.jpg"
            add_file :content_type => entry['type'], :content => File.read("/internal/sus_uploads/images/sus-#{sha1}-512.jpg"), :filename => filename
        end
        respond(:uploaded => 'yeah', :stored_path => "sus-#{sha1}")
    end

    get '/api/get_sus_photo/:slug' do
        require_user!
        slug = params[:slug]
        path = "/internal/sus_uploads/images/#{slug}"
        response.headers['Cache-Control'] = "max-age=#{3600 * 24 * 365}"
        respond_raw_with_mimetype(File.read(path), 'image/jpeg')
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

    post '/api/upload_sus_pdf' do
        require_user!
        entry = params['file']
        filename = entry['filename']
        blob = entry['tempfile'].read
        sha1 = Digest::SHA1.hexdigest(blob)[0, 16]
        path = "/internal/sus_uploads/pdf/sus-#{sha1}.pdf"
        File.open(path, 'w') do |f|
            f.write(blob)
        end
        display_name = @session_user[:display_name]
        deliver_mail("New PDF was uploaded by #{display_name} as sus-#{sha1}") do
            to WEBSITE_MAINTAINER_EMAIL
            bcc SMTP_FROM
            from SMTP_FROM

            subject "SuS PDF Upload from #{display_name}"

            filename = "sus-#{sha1}.pdf"
            add_file :content_type => entry['type'], :content => File.read("/internal/sus_uploads/pdf/sus-#{sha1}.pdf"), :filename => filename
        end
        respond(:uploaded => 'yeah', :stored_path => "sus-#{sha1}")
    end

    get '/api/get_sus_pdf/:slug' do
        require_user!
        slug = params[:slug]
        path = "/internal/sus_uploads/pdf/#{slug}.pdf"
        response.headers['Cache-Control'] = "max-age=#{3600 * 24 * 365}"
        respond_raw_with_mimetype(File.read(path), 'application/pdf')
    end

end
