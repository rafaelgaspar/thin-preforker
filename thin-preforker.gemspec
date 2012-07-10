# Maintain your gem's version:
require File.expand_path('../lib/thin/preforker/version', __FILE__)

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name = Thin::Preforker::NAME
  spec.version = Thin::Preforker::VERSION::STRING
  spec.description  = "A thin controller and spawner with prefork"
  spec.summary = "A thin controller and spawner with prefork" 
   
  spec.author = "Rafael Gaspar"
  spec.email = 'rafael.gaspar@me.com'
  spec.homepage = 'http://github.com/rafaelgaspar/thin-preforker/'
  
  spec.license  = 'MIT'
  
  spec.files = `git ls-files`.split($\)
  spec.executables = spec.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  spec.test_files = spec.files.grep(%r{^(test|spec|features)/})  
  spec.require_paths = ["lib"]
end
