module Thin
  module Preforker
    class Callbacks
      attr_accessor :before_fork_callbacks, :after_fork_callbacks
      
      def initialize filename = nil
        @before_fork_callbacks = []
        @after_fork_callbacks = []
        
        instance_eval(open(filename).read, filename) if filename
      end
      
      def run_before_fork_callbacks *args
        @before_fork_callbacks.each { |callback| callback.call(*args) }
      end
            
      def run_after_fork_callbacks *args
        @after_fork_callbacks.each { |callback| callback.call(*args) }
      end
      
      private
        def before_fork &block
          @before_fork_callbacks << block
        end        
      
        def after_fork &block
          @after_fork_callbacks << block
        end       
    end
  end
end