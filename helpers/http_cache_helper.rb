require 'sinatra/base'

module Sinatra
  module Helpers
    module HTTPCacheHelper
      REDIS = Redis.new(host: LinkedData.settings.redis_host, port: LinkedData.settings.redis_port)
      @@redis_available = nil

      ##
      # Check to see if the current object has a last modified, set via sinatra
      def check_last_modified(inst)
        return unless cache_enabled?
        cache_headers(inst.class)
        last_modified inst.last_modified || inst.cache_write
      end

      ##
      # Check to see if the current object's segment has a last modified, set via sinatra
      def check_last_modified_segment(inst)
        return unless cache_enabled?
        cache_headers(inst.class)
        last_modified inst.segment_last_modified || inst.cache_write
      end

      ##
      # Check to see if the collection has a last modified, set via sinatra
      def check_last_modified_collection(cls)
        return unless cache_enabled?
        cache_headers(cls)
        last_modified cls.collection_last_modified || cls.cache_collection_write
      end

      private

      def cache_enabled?
        @@redis_available ||= REDIS.ping.eql?("PONG") rescue false # Ping redis to make sure it's available
        return false unless @@redis_available
        return false unless LinkedData.settings.enable_http_cache
        return true
      end

      def cache_headers(cls)
        headers["Vary"] = "User-Agent, Accept, Accept-Language, Accept-Encoding, Authorization"
        headers["Cache-Control"] = "public, max-age=#{cls.max_age}"
      end
    end
  end
end

helpers Sinatra::Helpers::HTTPCacheHelper