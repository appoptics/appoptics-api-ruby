require 'base64'
require 'forwardable'

require 'appoptics/metrics/aggregator'
require 'appoptics/metrics/annotator'
require 'appoptics/metrics/client'
require 'appoptics/metrics/collection'
require 'appoptics/metrics/connection'
require 'appoptics/metrics/errors'
require 'appoptics/metrics/persistence'
require 'appoptics/metrics/queue'
require 'appoptics/metrics/smart_json'
require 'appoptics/metrics/util'
require 'appoptics/metrics/version'

module AppOptics

  # Metrics provides a simple wrapper for the Metrics web API with a
  # number of added conveniences for common use cases.
  #
  # See the {file:README.md README} for more information and examples.
  #
  # @example Simple use case
  #   AppOptics::Metrics.authenticate 'email', 'api_key'
  #
  #   # list current metrics
  #   AppOptics::Metrics.metrics
  #
  #   # submit a metric immediately
  #   AppOptics::Metrics.submit foo: 12712
  #
  #   # fetch the last 10 values of foo
  #   AppOptics::Metrics.get_measurements :foo, count: 10
  #
  # @example Queuing metrics for submission
  #   queue = AppOptics::Metrics::Queue.new
  #
  #   # queue some metrics
  #   queue.add foo: 12312
  #   queue.add bar: 45678
  #
  #   # send the metrics
  #   queue.submit
  #
  # @example Using a Client object
  #   client = AppOptics::Metrics::Client.new
  #   client.authenticate 'email', 'api_key'
  #
  #   # list client's metrics
  #   client.metrics
  #
  #   # create an associated queue
  #   queue = client.new_queue
  #
  #   # queue up some metrics and submit
  #   queue.add foo: 12345
  #   queue.add bar: 45678
  #   queue.submit
  #
  # @note Most of the methods you can call directly on AppOptics::Metrics are
  #   delegated to {Client} and are documented there.
  module Metrics
    extend SingleForwardable

    TYPES = [:counter, :gauge]
    PLURAL_TYPES = TYPES.map { |type| "#{type}s".to_sym }
    MIN_MEASURE_TIME = (Time.now-(3600*24*365)).to_i

    # Most of the singleton methods of AppOptics::Metrics are actually
    # being called on a global Client instance. See further docs on
    # Client.
    #
    def_delegators  :client, :agent_identifier, :annotate,
                    :api_endpoint, :api_endpoint=, :authenticate,
                    :connection, :create_snapshot, :delete_metrics,
                    :faraday_adapter, :faraday_adapter=, :get_composite,
                    :get_measurements, :get_metric, :get_series,
                    :get_snapshot, :get_source, :metrics,
                    :persistence, :persistence=, :persister, :proxy, :proxy=,
                    :sources, :submit, :update_metric, :update_metrics,
                    :update_source

    # The AppOptics::Metrics::Client being used by module-level
    # access.
    #
    # @return [Client]
    def self.client
      @client ||= AppOptics::Metrics::Client.new
    end

  end
end
