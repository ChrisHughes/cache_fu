require 'cache_fu'
require 'rails'

module ActsAsCached
  class Railtie < Rails::Railtie
    config.cache_fu = ActiveSupport::OrderedOptions.new
    initializer "cache_fu.configure" do |app|
      # Set default
      if !app.config.cache_fu.has_key? :perform_caching
        app.config.cache_fu[:perform_caching] = true
      end
      # Set value
      ActsAsCached.config[:perform_caching] = app.config.cache_fu[:perform_caching]
    end
    initializer 'cache_fu.extends' do
      ActiveSupport.on_load :active_record do
        extend ActsAsCached::Mixin
      end

      if File.exists?(config_file = Rails.root.join('config', 'memcached.yml'))
        ActsAsCached.config.stringify_keys!
        ActsAsCached.config.merge!(YAML.load(ERB.new(IO.read(config_file)).result))
      end

      ActiveSupport.on_load :action_controller do
        include ActsAsCached::MemcacheRuntime
      end
    end
  end
end
