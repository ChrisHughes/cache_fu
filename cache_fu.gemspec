Gem::Specification.new do |s|
  s.name = 'cache_fu'
  s.version = '0.3.0'
  s.authors = ["Chris Hughes"]
  s.summary = 'Makes caching easy for ActiveRecord models'
  s.description = "This gem is a fork of (http://github.com/kreetitech/cache_fu)."
  s.email = ['89dragon@gmail.com']

  s.files = Dir.glob('{lib,test,defaults}/**/*') +
                        %w(LICENSE README.md)
  s.homepage = 'http://github.com/chrishughes/cache_fu'
  s.require_paths = ["lib"]

  s.add_runtime_dependency 'rails', '>= 2.3'

  # Line commented to avoid duplicate dependency warning
  #s.add_development_dependency 'rails', '>= 2.3'
end
