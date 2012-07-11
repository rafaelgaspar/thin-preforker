module Thin
  module Preforker
    class Controller < Thin::Controllers::Cluster
      def initialize options
        @options = options
        
        if @options[:socket]
          @options.delete(:address)
          @options.delete(:port)
        end
        
        GC.copy_on_write_friendly = true if GC.respond_to?(:copy_on_write_friendly=) 
      end
      
      # Start the servers
      def start
        daemonize_prefoker if @options[:daemonize]
                        
        with_each_server do |n|
          start_server n, app
        end
        
        Process.waitall
      end
      
      # Start a single server
      def start_server(number, app)
        log "Starting server on #{server_id(number)} ... "
        
        server = Thin::Server.new(server_options_for(number)[:socket] || server_options_for(number)[:address],
                            server_options_for(number)[:port],
                            server_options_for(number))
          
        # Set options
        server.pid_file                       = server_options_for(number)[:pid]
        server.log_file                       = server_options_for(number)[:log]
        server.timeout                        = server_options_for(number)[:timeout]
        server.maximum_connections            = server_options_for(number)[:max_conns]
        server.maximum_persistent_connections = server_options_for(number)[:max_persistent_conns]
        server.threaded                       = server_options_for(number)[:threaded]
        server.no_epoll                       = server_options_for(number)[:no_epoll] if server.backend.respond_to?(:no_epoll=)
          
        # ssl support
        if server_options_for(number)[:ssl]
          server.ssl = true
          server.ssl_options = { :private_key_file => server_options_for(number)[:ssl_key_file], :cert_chain_file => server_options_for(number)[:ssl_cert_file], :verify_peer => server_options_for(number)[:ssl_verify] }
        end
        
        before_fork_for(server, number)
                      
        Process.fork do
          after_fork_for(server, number)
          
          # Constantize backend class
          server_options_for(number)[:backend] = eval(server_options_for(number)[:backend], TOPLEVEL_BINDING) if server_options_for(number)[:backend]
          
          # +config+ must be called before changing privileges since it might require superuser power.
          server.config
          
          server.change_privilege server_options_for(number)[:user], server_options_for(number)[:group] if server_options_for(number)[:user] && server_options_for(number)[:group]
          
          # Set app already loaded
          server.app = app
          
          # If a prefix is required, wrap in Rack URL mapper
          server.app = Rack::URLMap.new(server_options_for(number)[:prefix] => server.app) if server_options_for(number)[:prefix]
          
          # If a stats URL is specified, wrap in Stats adapter
          server.app = Thin::Stats::Adapter.new(server.app, server_options_for(number)[:stats]) if server_options_for(number)[:stats]

          server.start
        end
        
        wait_for_file :creation, server_options_for(number)[:pid]
      end
      
      # Stop the servers
      def stop
        with_each_server do |n|
          stop_server n
        end
      end
      
      # Stop a single server
      def stop_server(number)
        log "Stopping server on #{server_id(number)} ... "
        
        raise Thin::OptionRequired, :pid unless @options[:pid]
        
        tail_log(server_options_for(number)[:log]) do
          if Server.kill(server_options_for(number)[:pid], server_options_for(number)[:force] ? 0 : (server_options_for(number)[:timeout] || 60))
            wait_for_file :deletion, server_options_for(number)[:pid]
          end
        end
      end
      
      # Stop and start the servers.
      def restart
        daemonize_prefoker if @options[:daemonize]
        
        with_each_server do |n|
          stop_server n
          start_server n, app
          sleep 0.1 # Let the OS breath
        end
        
        Process.waitall
      end
      
      private
        def app
          # If a Rack config file is specified we eval it inside a Rack::Builder block to create
          # a Rack adapter from it. Or else we guess which adapter to use and load it.
          @app ||= @options[:rackup] ? load_rackup_config : load_adapter
        end
        
        def callbacks
          @callbacks ||= Callbacks.new @options[:callbacks]
        end
      
        def server_options_for(number)
          @server_options ||= {}
          return @server_options[number] if @server_options[number]
          
          # Sets the server options for this server
          @server_options[number] = @options.reject { |option, value| CLUSTER_OPTIONS.include?(option) }
          @server_options[number].merge!(:pid => pid_file_for(number), :log => log_file_for(number), :daemonize => nil)
          if socket
            @server_options[number].merge!(:socket => socket_for(number))
          elsif swiftiply?
            @server_options[number].merge!(:port => first_port)
          else
            @server_options[number].merge!(:port => number)
          end
          
          return @server_options[number]
        end
        
        def logs_to_reopen
          require 'fcntl'
          
          logs = []
          
          
          logs
        end
        
        def reopen_logs logs
          ObjectSpace.each_object(File) { |fp| fp.reopen(fp.path, "a") if logs.include? fp.path }
        end
        
        def before_fork_for(server, number)
          raise ArgumentError, "You must specify a pid file to fork" unless server_options_for(number)[:pid]
          raise ArgumentError, "You must specify a log file to fork" unless server_options_for(number)[:log]
          
          server.send(:remove_stale_pid_file)
          
          @pwd = Dir.pwd # Current directory is changed during fork, so store it
          
          FileUtils.mkdir_p File.dirname(server_options_for(number)[:pid])
          FileUtils.mkdir_p File.dirname(server_options_for(number)[:log])
          
          @logs = []
          ObjectSpace.each_object(File) { |fp| @logs << fp.path if fp.fcntl(Fcntl::F_GETFL) == File::APPEND | File::WRONLY rescue false }
        
          callbacks.run_before_fork_callbacks server, number
        end
      
        def after_fork_for(server, number)
          log_fp = open(server_options_for(number)[:log], "a")
          log_fp.sync = true
          $stdout.reopen(log_fp)
          $stderr.reopen(log_fp)
          $stdin.reopen("/dev/null")
          
          $0 = server.name
          
          Dir.chdir(@pwd)
          
          server.send(:write_pid_file)
          server.send(:at_exit) do
            log ">> Exiting!"
            server.send(:remove_pid_file)
          end
          
          Signal.trap("INT") { server.stop! }
          Signal.trap("TERM") { server.stop }
          Signal.trap("QUIT") { server.stop } unless Thin.win?
          
          ObjectSpace.each_object(File) { |fp| fp.reopen(fp.path, "a") if @logs.include? fp.path }
          
          callbacks.run_after_fork_callbacks server, number
        end
        
        def daemonize_prefoker
          raise ArgumentError, "You must specify a preforker pid file to daemonize" unless @options[:preforker_pid]
          raise ArgumentError, "You must specify a preforker log file to daemonize" unless @options[:preforker_log]
          
          pwd = Dir.pwd # Current directory is changed during fork, so store it
          
          FileUtils.mkdir_p File.dirname(@options[:preforker_pid])
          FileUtils.mkdir_p File.dirname(@options[:preforker_log])
                    
          Daemonize.daemonize @options[:preforker_log], "thin-preforker"
          
          Dir.chdir(pwd)
          
          Daemonize.redirect_io @options[:preforker_log]
          
          log ">> Writing PID to #{@options[:preforker_pid]}"
          open(@options[:preforker_pid],"w") { |f| f.write(Process.pid) }
          File.chmod(0644, @options[:preforker_pid])
        end          
    end
  end
end