# ===========================================================================
# Copyright: ©2011 Paul Lambert <paul@matygo.com> & Sproutcore Contributors
#            For Abbot, and licensed under same terms as Sproutcore itself
# ===========================================================================

require 'open-uri'
require 'thread'
require 'yaml'
require 'digest/md5'
  
module SC
  class Tools

    desc "jstd TARGET [OPTIONS]", "Generates configuration file for JsTestDriver (http://code.google.com/p/js-test-driver/wiki/ConfigurationFile)"
    method_options  :daemonize  => false,
                    :pid        => :string,
                    :port       => :string,
                    :jstdport   => :string,
                    :jstdhost   => :string,
                    :jstdconfpath => :string,
                    :jstdproxy  => :string,
                    :projroot	  => :string,
                    :jasminejs 	=> :string,
                    :jasmineadapter => :string,
                    :app        => :string,
                    :host       => :string,
                    :confhost	  => :string,
                    :irb        => false,
                    :filesystem => true

    def jstd(*targets)
      require 'nokogiri'
      
      # set defaults
      port = options[:port] = options[:port] || "4225"
      jstdport = options[:jstdport] || "4224"
      jstdhost = options[:jstdhost] || "http://localhost"
      jstdconfpath = options[:jstdconfpath] || "jsTestDriver.conf"
      jstdproxy = options[:jstdproxy] || '{matcher: "/static/*", server: "http://localhost:4225/"}'
      projroot = options[:projroot] || ""
      jasminejs = options[:jasminejs]
      jasmineadapter = options[:jasmineadapter]
      host = options[:host] || "http://localhost"
      confhost = options[:confhost] || "http://localhost"
      SC.module_url_prefix = "#{host}:#{port}"
      
      # find app target
      target = requires_target!(*targets)
      fatal! "Target must be an app" unless target[:target_type] == :app
      target_name = target[:target_name].to_s
      
      project = requires_project!
      # apparently necessary as getting target results in connections being refused
      # unless project is subsequently reloaded
      project.reload! 
      
      # wrap logic to rebuild configuration file in a Proc/closure
      # allowing for it to be rebuilt 'on the fly', which makes for
      # a much nicer testing loop. See rack/builder.rb for monitoring and 
      # invokation of this callback
      project.monitor_proc = Proc.new do 
        url = "#{host}:#{port}#{target_name}/en/current/tests.html"
        doc = Nokogiri::HTML(open(url))
        dir = "#{project.project_root}/tmp/jstd"
        Dir.mkdir(dir) if not Dir.exists?(dir)
        
        loadPaths = []
        
        if (jasminejs && jasmineadapter)
          loadPaths << projroot + jasminejs
          loadPaths << projroot + jasmineadapter
        end
        
        doc.css('script').each do |link|
          js = link['src']
          if js
            if (js != "/static/jasmine-sproutcore/en/current/source/jasmine.js")
              loadPaths << "#{confhost}:#{port}#{js}"
            end
          elsif (link.content and link.content.length > 0)
            js = link.content

            filename = "#{dir}/#{Digest::MD5.hexdigest(js)}.js"
            File.open(filename, "w") do |f|
              f.write(js)
            end
            
            loadPaths << "#{projroot}/tmp/jstd/#{Digest::MD5.hexdigest(js)}.js"
          end
        end
        project.nomonitor_pattern = Regexp.new(Regexp.escape(jstdconfpath))
        
        # write out to yaml conf
        conf = {"server"=>"#{jstdhost}:#{jstdport}", "load"=>loadPaths} 
        File.open(jstdconfpath, "w") do |f|
          f.write(YAML::dump(conf))
        end
        File.open(jstdconfpath, "a") {|f| f.write("proxy: \n- #{jstdproxy}") }
        
        SC.logger.info "Wrote to #{jstdconfpath}" 
      end
      
      Thread.new do 
        sleep(4)  # give server a chance to start up
        project.monitor_proc.call # call once to make sure everything's fresh and valid
      end

      server()
    end

  end
end
