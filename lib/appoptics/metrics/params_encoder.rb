module AppOptics
  module Metrics
    module ParamsEncoder
      SUBKEY_REGEXP = /\[|\]/

      def self.encode(params)
        return encode_tags(params) if params["tags"]
        Faraday::NestedParamsEncoder.encode(params)
      end

      def self.encode_tags(params)
        query_string = ""
        # Helper proc
        to_query = proc do |parent, obj, key|
          obj.keys.zip(obj.values).each do |k, v|
            if v.is_a?(Hash)
              to_query.call(parent, v, k)
            elsif v.is_a?(Array) && key
              v.each do |vv|
                query_string << nested_key(key, k, vv)
              end
            else
              if key
                query_string << nested_key(key, k, v)
              else
                query_string << "#{k}=#{v}&"
              end
            end
          end
          query_string
        end
        result = to_query.call(query_string, params)
        if result[-1] == "&"
          result = result[0..-2]
        end
        result
      end

      def self.decode(query)
        params = {}
        query.split("&").each do |pair|
          key, value = pair.split("=", 2)
          keys = key.split(SUBKEY_REGEXP)
          if keys.size > 1 # is subkey
            params[keys[0]] ||= {}
            if !params[keys[0]][keys[1]]
              params[keys[0]][keys[1]] = value
            else
              old_value = params[keys[0]][keys[1]]
              if !old_value.is_a?(Array)
                params[keys[0]][keys[1]] = []
                params[keys[0]][keys[1]] << old_value
              end
              params[keys[0]][keys[1]] << value
            end
          else
            params[key] = value
          end
        end
        params
      end

      def self.nested_key(key, subkey, value)
        "#{key}[#{subkey}]=#{value}&"
      end
    end
  end
end
