require File.dirname(__FILE__) + '/acts_as_cached/config'
require File.dirname(__FILE__) + '/acts_as_cached/cache_methods'
require File.dirname(__FILE__) + '/acts_as_cached/benchmarking'
require File.dirname(__FILE__) + '/acts_as_cached/disabled'
require File.dirname(__FILE__) + '/acts_as_cached/railtie' if defined?(Rails::Railtie)

module ActsAsCached
  @@config = {}
  mattr_reader :config

  def self.config=(options)
    @@config = Config.setup options
  end

  def self.skip_cache_gets=(boolean)
    ActsAsCached.config[:skip_gets] = boolean
  end

  module Mixin
    def acts_as_cached(options = {})
      extend  ClassMethods
      include InstanceMethods

      extend  Extensions::ClassMethods    if defined? Extensions::ClassMethods
      include Extensions::InstanceMethods if defined? Extensions::InstanceMethods

      options.symbolize_keys!

      # convert the find_by shorthand
      if find_by = options.delete(:find_by)
        options[:finder]   = "find_by_#{find_by}".to_sym
        options[:cache_id] = find_by
      end

      cache_config.replace  options.reject { |key,| not Config.valued_keys.include? key }
      cache_options.replace options.reject { |key,| Config.valued_keys.include? key }
    end
  end
end
ActiveRecord::Base.send :extend, ActsAsCached::Mixin
Rails::Application.initializer("cache_fu") do
  Object.send :include, ActsAsCached::Mixin
  #ActsAsCached.config = YAML.load(ERB.new(IO.read(config_file)).result)
  ActsAsCached.config = {}
end
