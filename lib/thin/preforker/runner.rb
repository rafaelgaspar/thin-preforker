class Thin::Preforker::Runner < Thin::Runner
  # Error raised that will abort the process and print not backtrace.
  class RunnerError < RuntimeError; end
  
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