require 'json'
module ActsAsCached
  module ClassMethods
    @@nil_sentinel = :_nil

    def cache_config
      @cache_config ||= {}
    end
    
    def cache_options(options={})
      cache_config[:options] ||= {}
      cache_config[:options].merge(filter_options(options))
    end
    
    def filter_options(options)
      # Returns options without keys specific to memcached included
      options.reject{|k| ActsAsCached.valued_keys.include?(k)}
    end
    
    def get_cache_id(args, options)
      # Returns optimized cache id string
      output = ""
      if options.is_a?(String)
        options_string = options
      end
      options_string ||= filter_options(options).to_json
      output += "#{args.first.to_s}"
      if options_string != "{}"
        output += "#{cache_key_separator}#{options_string}"
      end
      output
    end
    
    def get_cache_ids(args, options)
      # Gets cache ids for multiple values
      options_string = filter_options(options).to_json
      # Flatten array and process for each
      args.flatten.map{|arg| get_cache_id([arg.to_s], options_string)}
    end
    
    def get_cache(*args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      args    = args.flatten

      ##
      # head off to get_caches if we were passed multiple cache_ids
      if args.size > 1
        return get_caches(args, options)
      end

      # Generate unique cache_id
      cache_id = get_cache_id(args, options)
      search_id = args.first

      if (item = fetch_cache(cache_id, options)).nil?
        set_cache(cache_id, block_given? ? yield : fetch_cachable_data(search_id, options), options)
      else
        @@nil_sentinel == item ? nil : item
      end
    end

    ##
    # This method accepts an array of cache_ids which it will use to call
    # get_multi on your cache store.  Any misses will be fetched and saved to
    # the cache, and a hash keyed by cache_id will ultimately be returned.
    #
    def get_caches(*args)
      options   = args.last.is_a?(Hash) ? args.pop : {}
      
      # Create unique cache keys
      cache_ids = get_cache_ids(args, options)

      # Create array of cache keys to get
      cache_keys = cache_keys(cache_ids, options)
      
      # Create search id map
      search_ids = args.flatten.map{|arg| arg.to_s}
      
      # Map memcache keys to object cache_ids in { memcache_key => object_id } format
      search_keys_map = Hash[*cache_keys.zip(search_ids).flatten]

      # Call get_multi and figure out which keys were missed based on what was a hit
      hits = Rails.cache.read_multi(*cache_keys) || {}

      # Misses can take the form of key => nil
      hits.delete_if { |key, value| value.nil? }

      misses = cache_keys - hits.keys
      hits.each { |k, v| hits[k] = nil if v == @@nil_sentinel }

      # Return our hash if there are no misses
      return hits.values.index_by(&:cache_id) if misses.empty?

      # Find any missed records
      needed_ids     = search_keys_map.values_at(*misses)
      missed_records = Array(fetch_cachable_data(needed_ids, options))

      # Cache the missed records
      missed_records.each { |missed_record| missed_record.set_cache(options) }

      # Return all records as a hash indexed by object cache_id
      (hits.values + missed_records).index_by(&:cache_id)
    end

    # simple wrapper for get_caches that
    # returns the items as an ordered array
    def get_caches_as_list(*args)
      cache_ids = args.last.is_a?(Hash) ? args.first : args
      cache_ids = [cache_ids].flatten.compact.map(&:to_s)
      hash      = get_caches(*args)

      cache_ids.map do |key|
        hash[key]
      end
    end

    def set_cache(cache_id, value, options = nil)
      v = value.nil? ? @@nil_sentinel : value
      Rails.cache.write(cache_key(cache_id, options), v, cache_options(options))
      value
    end

    def expire_cache(cache_id = nil, options = {})
      Rails.cache.delete(cache_key(cache_id, options))
      true
    end
    alias :clear_cache :expire_cache

    def reset_cache(*args)
      options = args.last.is_a?(Hash) ? args.pop : {}
      args    = args.flatten

      # Detect any read/write splitting gems
      if defined?(Makara)
        connection.stick_to_master!
      end

      ##
      # head off to reset_caches if we were passed multiple cache_ids
      if args.size > 1
        return reset_caches(args, options)
      end

      # Generate unique cache_id
      cache_id = get_cache_id(args, options)
      search_id = args.first
      if defined?(DbCharmer)
        set_cache(cache_id, on_master.fetch_cachable_data(search_id, options), cache_options(options))
      else
        set_cache(cache_id, fetch_cachable_data(search_id, options), cache_options(options))
      end
    end
    
    def reset_caches(*args)
      options   = args.last.is_a?(Hash) ? args.pop : {}

      # Detect any read/write splitting gems
      if defined?(Makara)
        connection.stick_to_master!
      end

      # Create search id map
      search_ids = args.flatten.map{|arg| arg.to_s}
      
      # Retreives all records
      if defined?(DbCharmer)
        records = Array(on_master.fetch_cachable_data(search_ids, options))
      else
        records = Array(fetch_cachable_data(search_ids, options))
      end

      # Cache the missed records
      records.each { |record| record.set_cache(options) }
      
      # Return all records to user
      records
    end

    ##
    # Encapsulates the pattern of writing custom cache methods
    # which do nothing but wrap custom finders.
    #
    #   => Story.caches(:find_popular)
    #
    #   is the same as
    #
    #   def self.cached_find_popular
    #     get_cache(:find_popular) { find_popular }
    #   end
    #
    #  The method also accepts both a :ttl and/or a :with key.
    #  Obviously the :ttl value controls how long this method will
    #  stay cached, while the :with key's value will be passed along
    #  to the method.  The hash of the :with key will be stored with the key,
    #  making two near-identical #caches calls with different :with values utilize
    #  different caches.
    #
    #  => Story.caches(:find_popular, :with => :today)
    #
    #  is the same as
    #
    #   def self.cached_find_popular
    #     get_cache("find_popular/today") { find_popular(:today) }
    #   end
    #
    # If your target method accepts multiple parameters, pass :withs an array.
    #
    # => Story.caches(:find_popular, :withs => [ :one, :two ])
    #
    # is the same as
    #
    #   def self.cached_find_popular
    #     get_cache("find_popular/onetwo") { find_popular(:one, :two) }
    #   end
    def caches(method, options = {})
      if options.keys.include?(:with)
        with = options.delete(:with)
        get_cache("#{method}#{cache_key_separator}#{with}", options) { send(method, with) }
      elsif withs = options.delete(:withs)
        get_cache("#{method}#{cache_key_separator}#{withs}", options) { send(method, *withs) }
      else
        get_cache(method, options) { send(method) }
      end
    end
    alias :cached :caches

    def cached?(cache_id = nil)
      Rails.cache.exist?(cache_key(cache_id))
    end
    alias :is_cached? :cached?

    def fetch_cache(cache_id, options = {})
      Rails.cache.read(cache_key(cache_id, options))
    end

    def fetch_cachable_data(cache_id = nil, options = {})
      finder = cache_config[:finder] || :find
      return send(finder, filter_options(options)) unless cache_id

      args = [cache_id, filter_options(options)]
      # Cache options added to write instead for ttl settings
      #args << cache_options.dup unless cache_options.blank?
      send(finder, *args)
    end

    def cache_namespace
      Rails.cache.respond_to?(:namespace) ? Rails.cache.namespace : ActsAsCached.config[:namespace]
    end

    # Memcache-client automatically prepends the namespace, plus a colon, onto keys, so we take that into account for the max key length.
    # Rob Sanheim
    def max_key_length
      unless @max_key_length
        key_size = cache_config[:key_size] || 250
        @max_key_length = cache_namespace ? (key_size - cache_namespace.length - 1) : key_size
      end
      @max_key_length
    end

    def cache_name
      @cache_name ||= respond_to?(:model_name) ? model_name.cache_key : name
    end

    def cache_keys(cache_ids, options = {})
      cache_ids.flatten.map { |cache_id| cache_key(cache_id, options) }
    end

    def cache_key(cache_id, options = {})
      # Generate cache key
      namespace = ""
      if options[:namespace]
        namespace = options[:namespace].to_s + ":"
      end
      key = [cache_name, cache_config[:version], cache_id].compact.join(cache_key_separator).gsub(' ', '_')
      if key.length + namespace.length > max_key_length
        # Hash if key exceeds max_key_length
        key = Digest::MD5.hexdigest(key)
      end
      output = namespace + key
      output[0..(max_key_length - 1)]
    end
    
    def cache_key_separator
      @cache_key_separator ||= ActsAsCached.config[:separator] || "/"
    end
  end

  module InstanceMethods
    def self.included(base)
      base.send :delegate, :cache_config,  :to => 'self.class'
      base.send :delegate, :cache_options, :to => 'self.class'
    end

    def get_cache(key = nil, options = {}, &block)
      self.class.get_cache(cache_id(key), options, &block)
    end

    def set_cache(options = nil)
      self.class.set_cache(cache_id, self, options)
    end

    def reset_cache(key = nil)
      self.class.reset_cache(cache_id(key))
    end

    def expire_cache(key = nil)
      self.class.expire_cache(cache_id(key))
    end
    alias :clear_cache :expire_cache

    def cached?(key = nil)
      self.class.cached? cache_id(key)
    end

    def cache_id(key = nil)
      cid = case
            when new_record?
              "new"
            when timestamp = self[:updated_at]
              timestamp = timestamp.utc.to_s(:number)
              "#{id}-#{timestamp}"
            else
              id.to_s
            end
      key.nil? ? cid : "#{cid}#{self.class.cache_key_separator}#{key}"
    end

    def caches(method, options = {})
      key = "#{self.cache_key}#{self.class.cache_key_separator}#{method}"
      if options.keys.include?(:with)
        with = options.delete(:with)
        self.class.get_cache("#{key}#{self.class.cache_key_separator}#{with}", options) { send(method, with) }
      elsif withs = options.delete(:withs)
        self.class.get_cache("#{key}#{self.class.cache_key_separator}#{withs}", options) { send(method, *withs) }
      else
        self.class.get_cache(key, options) { send(method) }
      end
    end
    alias :cached :caches

    # Ryan King
    def set_cache_with_associations
      Array(cache_options[:include]).each do |assoc|
        send(assoc).reload
      end if cache_options[:include]
      set_cache
    end

    # Lourens Naud
    def expire_cache_with_associations(*associations_to_sweep)
      (Array(cache_options[:include]) + associations_to_sweep).flatten.uniq.compact.each do |assoc|
        Array(send(assoc)).compact.each { |item| item.expire_cache if item.respond_to?(:expire_cache) }
      end
      expire_cache
    end
  end
end
