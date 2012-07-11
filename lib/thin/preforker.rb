require "thin"

module Thin
  module Preforker
    autoload :Callbacks, "thin/preforker/callbacks"
    autoload :Controller, "thin/preforker/controller"
    autoload :Runner, "thin/preforker/runner"
    autoload :Version, "thin/preforker/version"
  end
end