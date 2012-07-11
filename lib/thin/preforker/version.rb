unless defined?(Thin::Preforker::VERSION)
  module Thin
    module Preforker
      module VERSION #:nodoc:
        MAJOR = 0
        MINOR = 0
        TINY = 2
    
        STRING = [MAJOR, MINOR, TINY].join('.')
      end
  
      NAME = 'thin-preforker'.freeze
      SERVER = "#{NAME} #{VERSION::STRING}".freeze
    end
  end
end