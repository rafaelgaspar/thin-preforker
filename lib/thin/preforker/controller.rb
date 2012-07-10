module Thin
  module Preforker
    class Controller < Thin::Controllers::Cluster
      def initialize *args
        super
        
        GC.copy_on_write_friendly = true if GC.respond_to?(:copy_on_write_friendly=)  
      end
      
      # Start the servers
      def start
        with_each_server do |n|
          start_server n, app
          sleep 0.1 # Let the OS breath
        end
      end
      
      # Start a single server
      def start_server(number, app)
        log "Starting server on #{server_id(number)} ... "
        
        # Save the log files
        logs = logs_to_reopen
        
        # Force GC to collect before forking
        GC.start
                        
        fork do
          $stdout.reopen($stdout)
          $stderr.reopen($stderr)
          $stdin.reopen("/dev/null")
          
          # Constantize backend class
          server_options_for(number)[:backend] = eval(server_options_for(number)[:backend], TOPLEVEL_BINDING) if server_options_for(number)[:backend]
          
          server = Thin::Server.new(server_options_for(number)[:socket] || server_options_for(number)[:address], # Server detects kind of socket
                              server_options_for(number)[:port],                         # Port ignored on UNIX socket
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
          
          # Detach the process, after this line the current process returns
          server.daemonize if server_options_for(number)[:daemonize]
          
          # +config+ must be called before changing privileges since it might require superuser power.
          server.config
          
          server.change_privilege server_options_for(number)[:user], server_options_for(number)[:group] if server_options_for(number)[:user] && server_options_for(number)[:group]
          
          # Set app already loaded
          server.app = app
          
          # If a prefix is required, wrap in Rack URL mapper
          server.app = Rack::URLMap.new(server_options_for(number)[:prefix] => server.app) if server_options_for(number)[:prefix]
          
          # If a stats URL is specified, wrap in Stats adapter
          server.app = Thin::Stats::Adapter.new(server.app, server_options_for(number)[:stats]) if server_options_for(number)[:stats]
          
          reopen_logs logs

          server.start
        end
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
        app
        
        with_each_server do |n|
          stop_server n
          start_server n, app
          sleep 0.1 # Let the OS breath
        end
      end
      
      private
        def app
          # If a Rack config file is specified we eval it inside a Rack::Builder block to create
          # a Rack adapter from it. Or else we guess which adapter to use and load it.
          @app ||= @options[:rackup] ? load_rackup_config : load_adapter
        end
      
        def server_options_for(number)
          @server_options ||= {}
          return @server_options[number] if @server_options[number]
          
          # Sets the server options for this server
          @server_options[number] = @options.reject { |option, value| CLUSTER_OPTIONS.include?(option) }
          @server_options[number].merge!(:pid => pid_file_for(number), :log => log_file_for(number))
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
          ObjectSpace.each_object(File) { |fp| logs << fp.path if fp.fcntl(Fcntl::F_GETFL) == File::APPEND | File::WRONLY rescue false }
          
          logs
        end
        
        def reopen_logs logs
          ObjectSpace.each_object(File) { |fp| fp.reopen(fp.path, "a") if logs.include? fp.path }
        end
    end
  end
end