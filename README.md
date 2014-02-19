
#Modified version of Cache_Fu

##Changes from Surendra Singhi's version

* Adds support for complex queries with multiple parameter parts

* Adds ability to pass expires_in to acts_as_cached

* Allows enabling or disabling of caching with config.cache_fu.perform_caching in environment file

* Adds ability to use cache namespacing

* Supports master / slave database read / write splitting, where resetting the cache reads from the database master for both Makara and DbCharmer

* Adds key hashing for keys that exceed max length

* Adds global configuration inheritance from config.cache_fu

##Examples

###Setting a cache expiry time on a per-model basis

Setting expires_in in the model allows overriding the default set with dalli or any other Rails cache being used.

```ruby
acts_as_cached :expires_in => 5.minutes
````

###Setting a cache item's namespace

There are multiple ways to use cache namespaces. One example of why you might want to would be to keep each user's account number as the namespace, making it easy to clear all queries associated with that account when we want our cache updated.

Namespacing, in this example, works by assigning a unique numerical prefix, assigned on a revolving basis, to each account id. This unique number is the namespace. This prefix is added before each cache key, rendering it unique to that namespace. We then store the namespace to account association in memcache as a separate key, and look it up before each request. When we want to invalidate the account, we simply change the cache association stored in memcache.

```ruby
module CacheController
  @@config = {
    :namespace_token => "ns",
    :namespace_expires_in => 1.days,
  }
  def get_cache_namespace(id)
    # Gets a cache namespace or lease one
    nsid = find_cache_namespace(id).to_i
    if nsid < 1
      nsid = lease_cache_namespace(id)
    end
    nsid
  end

  def find_cache_namespace(id)
    # Finds an existing cache namespace or nil
    Rails.cache.read(@@config[:namespace_token] + "_" + id.to_s, :raw => true)
  end

  def lease_cache_namespace(id)
    # Leases a new cache namespace
    nsid = Rails.cache.increment(@@config[:namespace_token])
    Rails.cache.write(@@config[:namespace_token] + "_" + id.to_s, nsid, :expires_in => @@config[:namespace_expires_in], :raw => true)
    nsid
  end
end

\# Get request parameters from url
account_id = params[:account_id]
row_id = params[:photo_id]

\# Fetch or create namespace for this account
namespace = get_cache_namespace(account_id)

\# Get cache of this request in this namespace, or set cache if it doesn't exist
Photos.get_cache(row_id, :conditions => {:account => account_id}, :namespace => namespace)

\# Reset cache of this one request in this namespace
Photos.reset_cache(row_id, :conditions => {:account => account_id}, :namespace => namespace)

\# Reset cache for all requests in this namespace
namespace = lease_cache_namespace(account_id)
```

###Using with master / slave database replication

This gem has been modified to work with both DbCharmer[https://github.com/kovyrin/db-charmer] and Makara[https://github.com/taskrabbit/makara]. Both gems handle automatic routing of database writes to a master database, while reading from a faster slave database.

Either of these gems will be detected, and on_db or stick_to_master! will be called respectively.

#Original ReadMe

#cache_fu

A rewrite of acts_as_cached.
This version is only compatible with rails 3 and above.

This gem version uses Dalli.
If you want a memcache compatible version then see the branch memcache_client or use version 0.1.5 of the gem.

For fragment and page caching use Rails DalliStore as it already provides all the functionality.

This gem is very useful for caching in models.

##Changes from acts_as_cached 1

* You can no longer set a 'ttl' method on a class. Instead, pass :ttl to acts_as_cached: `acts_as_cached :ttl => 15.minutes`

* The is_cached? method is aliased as cached?

* set_cache on an instance can take a ttl: `@story.set_cache(15.days)`

##Author
[Surendra Singhi](ssinghi@kreeti.com)
