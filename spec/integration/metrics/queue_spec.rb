require 'spec_helper'

module AppOptics
  module Metrics

    describe Queue do
      before(:all) { prep_integration_tests }
      before(:each) do
        delete_all_metrics
      end

      context "with a large number of metrics" do
        it "submits them in multiple requests" do
          Middleware::CountRequests.reset
          queue = Queue.new(per_request: 3)
          (1..10).each do |i|
            queue.add "gauge_#{i}" => 1
          end
          queue.submit
          expect(Middleware::CountRequests.total_requests).to eq(4)
        end

        it "persists all metrics" do
          queue = Queue.new(per_request: 2)
          (1..5).each do |i|
            queue.add "gauge_#{i}" => i
          end
          queue.submit

          metrics = Metrics.metrics
          expect(metrics.length).to eq(8)
          gauge = Metrics.get_series :gauge_5
          expect(gauge['unassigned'][0]['value']).to eq(5)
        end

        it "applies globals to each request" do
          measure_time = Time.now.to_i-3
          queue = Queue.new(
            per_request: 3,
            tags: {
              host: 'localhost',
              environment: 'test'
            },
            measure_time: measure_time,
            skip_measurement_times: true
          )
          (1..5).each do |i|
            queue.add "gauge_#{i}" => 1
          end
          queue.submit

          # verify globals have persisted for all requests
          query = {
            duration: 300,
            resolution: 1
          }
          gauge = Metrics.get_series :gauge_5, query
          expect(gauge[0]["measurements"][0]["value"]).to eq(1.0)
        end
      end

      context "with tags" do
        let(:queue) { Queue.new(tags: { hostname: "metrics-web-stg-1" }) }

        it "respects default and individual tags" do
          queue.add test_1: 123
          queue.add test_2: { value: 456, tags: { hostname: "metrics-web-stg-2" }}
          queue.submit

          test_1 = AppOptics::Metrics.get_series :test_1, resolution: 1, duration: 3600
          expect(test_1[0]["tags"]["hostname"]).to eq("metrics-web-stg-1")
          expect(test_1[0]["measurements"][0]["value"]).to eq(123)

          test_2 = AppOptics::Metrics.get_series :test_2, resolution: 1, duration: 3600
          expect(test_2[0]["tags"]["hostname"]).to eq("metrics-web-stg-2")
          expect(test_2[0]["measurements"][0]["value"]).to eq(456)
        end
      end

    end

  end
end
