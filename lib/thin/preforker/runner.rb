class Thin::Preforker::Runner < Thin::Runner
  # Error raised that will abort the process and print not backtrace.
  class RunnerError < RuntimeError; end
  
  def initialize argv
    @argv = argv

    # Default options values
    @options = {
      :chdir                => Dir.pwd,
      :environment          => ENV['RACK_ENV'] || 'development',
      :address              => '0.0.0.0',
      :port                 => Thin::Server::DEFAULT_PORT,
      :timeout              => Thin::Server::DEFAULT_TIMEOUT,
      :log                  => 'log/thin.log',
      :pid                  => 'tmp/pids/thin.pid',
      :max_conns            => Thin::Server::DEFAULT_MAXIMUM_CONNECTIONS,
      :max_persistent_conns => Thin::Server::DEFAULT_MAXIMUM_PERSISTENT_CONNECTIONS,
      :require              => [],
      :wait                 => Thin::Preforker::Controller::DEFAULT_WAIT_TIME,
      :daemonize            => true,
      :preforker_callbacks  => nil,
      :preforker_log        => "log/thin-preforker.log",
      :preforker_pid        => "tmp/pids/thin-preforker.pid"
    }

    parse!
  end
  
  def parser
    super
    
    @parser.banner = "Usage: #{@parser.program_name} [options] #{self.class.commands.join('|')}"
      
    @parser.tap do |opts|
      # TODO change to #on instead of #on_tail after thin is fixed.
      opts.on_tail ""
      opts.on_tail "Preforker options:"
      
      opts.on_tail("--callbacks FILE", "Path to preforker callbacks file") { |file| @options[:callbacks] = file }
      opts.on_tail("--preforker-log FILE", "File to redirect preforker output " + "(default: #{@options[:preforker_log]})") { |file| @options[:preforker_log] = file }
      opts.on_tail("--preforker-pid FILE", "File to store preforker PID " + "(default: #{@options[:preforker_pid]})") { |file| @options[:preforker_pid] = file }
    end
  end
  
  
  def run_command
    load_options_from_config_file! unless CONFIGLESS_COMMANDS.include?(@command)
    
    # PROGRAM_NAME is relative to the current directory, so make sure
    # we store and expand it before changing directory.
    Thin::Command.script = File.expand_path($PROGRAM_NAME)

    # Change the current directory ASAP so that all relative paths are
    # relative to this one.
    Dir.chdir(@options[:chdir]) unless CONFIGLESS_COMMANDS.include?(@command)

    @options[:require].each { |r| ruby_require r }
    Thin::Logging.debug = @options[:debug]
    Thin::Logging.trace = @options[:trace]

    controller = Thin::Preforker::Controller.new(@options)

    if controller.respond_to?(@command)
      begin
        controller.send(@command, *@arguments)
      rescue RunnerError => e
        abort e.message
      end
    else
      abort "Invalid options for command: #{@command}"
    end
  end
end