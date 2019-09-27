module AppOptics
  module Metrics

    class Client
      extend Forwardable

      def_delegator :annotator, :add, :annotate

      attr_accessor :api_key, :proxy, :custom_headers, :client_timeout,
        :open_timeout, :retry_count

      # @example Have the gem build your identifier string
      #   AppOptics::Metrics.agent_identifier 'flintstone', '0.5', 'fred'
      #
      # @example Provide your own identifier string
      #   AppOptics::Metrics.agent_identifier 'flintstone/0.5 (dev_id:fred)'
      #
      # @example Remove identifier string
      #   AppOptics::Metrics.agent_identifier ''
      def agent_identifier(*args)
        if args.length == 1
          @agent_identifier = args.first
        elsif args.length == 3
          @agent_identifier = "#{args[0]}/#{args[1]} (dev_id:#{args[2]})"
        elsif ![0,1,3].include?(args.length)
          raise ArgumentError, 'invalid arguments, see method documentation'
        end
        @agent_identifier ||= ''
      end

      def annotator
        @annotator ||= Annotator.new(client: self)
      end

      # API endpoint to use for queries and direct
      # persistence.
      #
      # @return [String] api_endpoint
      def api_endpoint
        @api_endpoint ||= 'https://api.appoptics.com'
      end

      # Set API endpoint for use with queries and direct
      # persistence. Generally you should not need to set this
      # as it will default to the current Appoptics endpoint.
      #
      def api_endpoint=(endpoint)
        @api_endpoint = endpoint
      end

      # Authenticate for direct persistence
      #
      # @param [String] email
      # @param [String] api_key
      def authenticate(api_key)
        flush_authentication
        self.api_key = api_key
      end

      # Current connection object
      #
      def connection
        # prevent successful creation if no credentials set
        raise CredentialsMissing unless (self.api_key)
        @connection ||= Connection.new(client: self, api_endpoint: api_endpoint,
                                       adapter: faraday_adapter, proxy: self.proxy,
                                       client_timeout: client_timeout,
                                       open_timeout: open_timeout,
                                       retry_count: retry_count)
      end

      # Overrride user agent for this client's connections. If you
      # are trying to specify an agent identifier for developer
      # program, see #agent_identifier.
      #
      def custom_user_agent=(agent)
        @user_agent = agent
        @connection = nil
      end

      def custom_user_agent
        @user_agent
      end

      # Completely delete metrics with the given names. Be
      # careful with this, this is instant and permanent.
      #
      # @example Delete metric 'temperature'
      #   AppOptics::Metrics.delete_metrics :temperature
      #
      # @example Delete metrics 'foo' and 'bar'
      #   AppOptics::Metrics.delete_metrics :foo, :bar
      #
      # @example Delete metrics that start with 'foo' except 'foobar'
      #   AppOptics::Metrics.delete_metrics names: 'foo*', exclude: ['foobar']
      #
      def delete_metrics(*metric_names)
        raise(NoMetricsProvided, 'Metric name missing.') if metric_names.empty?
        if metric_names[0].respond_to?(:keys) # hash form
          params = metric_names[0]
        else
          params = { names: metric_names.map(&:to_s) }
        end
        connection.delete do |request|
          request.url connection.build_url("metrics")
          request.body = SmartJSON.write(params)
        end
        # expects 204, middleware will raise exception otherwise.
        true
      end

      # Return current adapter this client will use.
      # Defaults to Metrics.faraday_adapter if set, otherwise
      # Faraday.default_adapter
      def faraday_adapter
        @faraday_adapter ||= default_faraday_adapter
      end

      # Set faraday adapter this client will use
      def faraday_adapter=(adapter)
        @faraday_adapter = adapter
      end

      # Retrieve measurements for a given composite metric definition.
      # :start_time and :resolution are required options, :end_time is
      # optional.
      #
      # @example Get 5m moving average of 'foo'
      #   measurements = AppOptics::Metrics.get_composite
      #     'moving_average(mean(series("foo", "*"), {size: "5"}))',
      #     start_time: Time.now.to_i - 60*60, resolution: 300
      #
      # @param [String] definition Composite definition
      # @param [hash] options Query options
      def get_composite(definition, options={})
        unless options[:start_time] && options[:resolution]
          raise "You must provide a :start_time and :resolution"
        end
        query = options.dup
        query[:compose] = definition
        url = connection.build_url("metrics", query)
        response = connection.get(url)
        parsed = SmartJSON.read(response.body)
        # TODO: pagination support
        parsed
      end

      # Retrieve a specific metric by name, optionally including data points
      #
      # @example Get attributes for a metric
      #   metric = AppOptics::Metrics.get_metric :temperature
      #
      # @example Get a metric and its 20 most recent data points
      #   metric = AppOptics::Metrics.get_metric :temperature, count: 20
      #   metric['measurements'] # => {...}
      #
      # A full list of query parameters can be found in the API
      # documentation: {http://docs.appoptics.com/api/#retrieve-a-metric}
      #
      # @param [Symbol|String] name Metric name
      # @param [Hash] options Query options
      def get_metric(name, options = {})
        query = options.dup
        if query[:start_time].respond_to?(:year)
          query[:start_time] = query[:start_time].to_i
        end
        if query[:end_time].respond_to?(:year)
          query[:end_time] = query[:end_time].to_i
        end
        unless query.empty?
          query[:resolution] ||= 1
        end
        # expects 200
        url = connection.build_url("metrics/#{name}", query)
        response = connection.get(url)
        parsed = SmartJSON.read(response.body)
        # TODO: pagination support
        parsed
      end

      # Retrieve series of measurements for a given metric
      #
      # @example Get series for metric
      #   series = AppOptics::Metrics.get_series :requests, resolution: 1, duration: 3600
      #
      # @example Get series for metric grouped by tag
      #   query = { duration: 3600, resolution: 1, group_by: "environment", group_by_function: "sum" }
      #   series = AppOptics::Metrics.get_series :requests, query
      #
      # @example Get series for metric grouped by tag and negated by tag filter
      #   query = { duration: 3600, resolution: 1, group_by: "environment", group_by_function: "sum", tags_search: "environment=!staging" }
      #   series = AppOptics::Metrics.get_series :requests, query
      #
      # @param [Symbol|String] metric_name Metric name
      # @param [Hash] options Query options
      def get_series(metric_name, options={})
        raise ArgumentError, ":resolution and :duration or :start_time must be set" if options.empty?
        query = options.dup
        if query[:start_time].respond_to?(:year)
          query[:start_time] = query[:start_time].to_i
        end
        if query[:end_time].respond_to?(:year)
          query[:end_time] = query[:end_time].to_i
        end
        query[:resolution] ||= 1
        unless query[:start_time] || query[:end_time]
          query[:duration] ||= 3600
        end
        url = connection.build_url("measurements/#{metric_name}", query)
        response = connection.get(url)
        parsed = SmartJSON.read(response.body)
        parsed["series"]
      end

      # Retrieve data points for a specific metric
      #
      # @example Get 20 most recent data points for metric
      #   data = AppOptics::Metrics.get_measurements :temperature, count: 20
      #
      # @example Get the 20 most recent 15 minute data point rollups
      #   data = AppOptics::Metrics.get_measurements :temperature, count: 20,
      #                                            resolution: 900
      #
      # @example Get data points for the last hour
      #   data = AppOptics::Metrics.get_measurements start_time: Time.now-3600
      #
      # @example Get 15 min data points from two hours to an hour ago
      #   data = AppOptics::Metrics.get_measurements start_time: Time.now-7200,
      #                                            end_time: Time.now-3600,
      #                                            resolution: 900
      #
      # A full list of query parameters can be found in the API
      # documentation: {http://docs.appoptics.com/api/#retrieve-a-metric}
      #
      # @param [Symbol|String] metric_name Metric name
      # @param [Hash] options Query options
      def get_measurements(metric_name, options = {})
        raise ArgumentError, "you must provide at least a :start_time or :count" if options.empty?
        get_metric(metric_name, options)["measurements"]
      end

      # Purge current credentials and connection.
      #
      def flush_authentication
        self.api_key = nil
        @connection = nil
      end

      # List currently existing metrics
      #
      # @example List all metrics
      #   AppOptics::Metrics.metrics
      #
      # @example List metrics with 'foo' in the name
      #   AppOptics::Metrics.metrics name: 'foo'
      #
      # @param [Hash] options
      def metrics(options={})
        query = {}
        query[:name] = options[:name] if options[:name]
        offset = 0
        path = "metrics"
        Collection.paginated_metrics(connection, path, query)
      end

      # Create a new queue which uses this client.
      #
      # @return [Queue]
      def new_queue(options={})
        options[:client] = self
        Queue.new(options)
      end

      # Persistence type to use when saving metrics.
      # Default is :direct.
      #
      # @return [Symbol]
      def persistence
        @persistence ||= :direct
      end

      # Set persistence type to use when saving metrics.
      #
      # @param [Symbol] persist_method
      def persistence=(persist_method)
        @persistence = persist_method
      end

      # Current persister object.
      def persister
        @queue ? @queue.persister : nil
      end

      # Submit all queued metrics.
      #
      def submit(args)
        @queue ||= Queue.new(client: self,
                             skip_measurement_times: true,
                             clear_failures: true)
        @queue.add args
        @queue.submit
      end

      # Update a single metric with new attributes.
      #
      # @example Update metric 'temperature'
      #   AppOptics::Metrics.update_metric :temperature, period: 15, attributes: { color: 'F00' }
      #
      # @example Update metric 'humidity', creating it if it doesn't exist
      #   AppOptics::Metrics.update_metric 'humidity', type: :gauge, period: 60, display_name: 'Humidity'
      #
      def update_metric(metric, options = {})
        url = "metrics/#{metric}"
        connection.put do |request|
          request.url connection.build_url(url)
          request.body = SmartJSON.write(options)
        end
      end

      # Update multiple metrics.
      #
      # @example Update multiple metrics by name
      #   AppOptics::Metrics.update_metrics names: ["foo", "bar"], period: 60
      #
      # @example Update all metrics that start with 'foo' that aren't 'foobar'
      #   AppOptics::Metrics.update_metrics names: 'foo*', exclude: ['foobar'], display_min: 0
      #
      def update_metrics(metrics)
        url = "metrics" # update multiple metrics
        connection.put do |request|
          request.url connection.build_url(url)
          request.body = SmartJSON.write(metrics)
        end
      end

      # Retrive a snapshot, to check its progress or find its image_href
      #
      # @example Get a snapshot identified by 42
      #   AppOptics::Metrics.get_snapshot 42
      #
      # @param [Integer|String] id
      def get_snapshot(id)
        url = "snapshots/#{id}"
        response = connection.get(url)
        parsed = SmartJSON.read(response.body)
      end

    private

      def default_faraday_adapter
        if Metrics.client == self
          Faraday.default_adapter
        else
          Metrics.faraday_adapter
        end
      end

      def flush_persistence
        @persistence = nil
      end

    end

  end
end
