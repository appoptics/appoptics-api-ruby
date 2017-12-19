require 'spec_helper'

module AppOptics
  describe Metrics do
    before(:all) { prep_integration_tests }

    describe "#annotate" do
      before(:all) { @annotator = Metrics::Annotator.new }
      before(:each) { delete_all_annotations }

      it "creates new annotation" do
        Metrics.annotate :deployment, "deployed v68"
        annos = @annotator.fetch(:deployment, start_time: Time.now.to_i-60)
        expect(annos["events"]["unassigned"].length).to eq(1)
        expect(annos["events"]["unassigned"][0]["title"]).to eq('deployed v68')
      end
      it "supports sources" do
        Metrics.annotate :deployment, 'deployed v69', source: 'box1'
        annos = @annotator.fetch(:deployment, start_time: Time.now.to_i-60)
        expect(annos["events"]["box1"].length).to eq(1)
        first = annos["events"]["box1"][0]
        expect(first['title']).to eq('deployed v69')
      end
      it "supports start and end times" do
        start_time = Time.now.to_i-120
        end_time = Time.now.to_i-30
        Metrics.annotate :deployment, 'deployed v70', start_time: start_time,
                    end_time: end_time
        annos = @annotator.fetch(:deployment, start_time: Time.now.to_i-180)
        expect(annos["events"]["unassigned"].length).to eq(1)
        first = annos["events"]["unassigned"][0]
        expect(first['title']).to eq('deployed v70')
        expect(first['start_time']).to eq(start_time)
        expect(first['end_time']).to eq(end_time)
      end
      it "supports description" do
        Metrics.annotate :deployment, 'deployed v71', description: 'deployed foobar!'
        annos = @annotator.fetch(:deployment, start_time: Time.now.to_i-180)
        expect(annos["events"]["unassigned"].length).to eq(1)
        first = annos["events"]["unassigned"][0]
        expect(first['title']).to eq('deployed v71')
        expect(first['description']).to eq('deployed foobar!')
      end
    end

    describe "#delete_metrics" do
      before(:each) { delete_all_metrics }

      context 'with names' do

        context "with a single argument" do
          it "deletes named metric" do
            Metrics.submit foo: 123
            expect(Metrics.metrics(name: :foo)).not_to be_empty
            Metrics.delete_metrics :foo
            expect(Metrics.metrics(name: :foo)).to be_empty
          end
        end

        context "with multiple arguments" do
          it "deletes named metrics" do
            Metrics.submit foo: 123, bar: 345, baz: 567
            Metrics.delete_metrics :foo, :bar
            expect(Metrics.metrics(name: :foo)).to be_empty
            expect(Metrics.metrics(name: :bar)).to be_empty
            expect(Metrics.metrics(name: :baz)).not_to be_empty
          end
        end

        context "with missing metric" do
          it "runs cleanly" do
            # the API currently returns success even if
            # the metric has already been deleted or is absent.
            Metrics.delete_metrics :missing
          end
        end

        context "with no arguments" do
          it "does not make request" do
            expect {
              Metrics.delete_metrics
            }.to raise_error(Metrics::NoMetricsProvided)
          end
        end

      end

      context 'with patterns' do
        it "filters properly" do
          Metrics.submit foo: 1, foobar: 2, foobaz: 3, bar: 4
          Metrics.delete_metrics names: 'fo*', exclude: ['foobar']

          %w{foo foobaz}.each do |name|
            expect {
              Metrics.get_metric name
            }.to raise_error(AppOptics::Metrics::NotFound)
          end

          %w{foobar bar}.each do |name|
            Metrics.get_metric name # stil exist
          end
        end
      end
    end

    describe "#get_metric" do
      before(:all) do
        delete_all_metrics
        Metrics.submit my_gauge: {value: 0, measure_time: Time.now.to_i-60}
        1.upto(2).each do |i|
          measure_time = Time.now.to_i - (5+i)
          opts = {measure_time: measure_time}
          Metrics.submit my_gauge: opts.merge(value: i)
          Metrics.submit my_gauge: opts.merge(tags: { hostname: "baz"}, value: i+1)
        end
      end

      context "without arguments" do
        it "gets metric attributes" do
          metric = Metrics.get_metric :my_gauge
          expect(metric['name']).to eq('my_gauge')
          expect(metric['type']).to eq('gauge')
        end
      end

    end

    describe "#metrics" do
      before(:all) do
        delete_all_metrics
        Metrics.submit foo: 123, bar: 345, baz: 678, foo_2: 901
      end

      context "without arguments" do
        it "lists all metrics" do
          metric_names = Metrics.metrics.map { |metric| metric['name'] }
          expect(metric_names.sort).to eq(%w{foo bar baz foo_2}.sort)
        end
      end

      context "with a name argument" do
        it "lists metrics that match" do
          metric_names = Metrics.metrics(name: 'foo').map { |metric| metric['name'] }
          expect(metric_names.sort).to eq(%w{foo foo_2}.sort)
        end
      end

    end

    describe "#submit" do

      context "with a gauge" do
        before(:all) do
          delete_all_metrics
          Metrics.submit foo: 123
        end

        it "creates the metrics" do
          metric = Metrics.metrics[0]
          expect(metric['name']).to eq('foo')
          expect(metric['type']).to eq('gauge')
        end

        it "stores their data" do
          data = Metrics.metrics(name: 'foo')
          expect(data.count).to eq(1)
        end
      end

    end

    describe "#update_metric[s]" do

      context 'with a single metric' do
        context "with an existing metric" do
          before do
            delete_all_metrics
            Metrics.submit foo: 123
          end

          it "updates the metric" do
            Metrics.update_metric :foo, display_name: "Foo Metric",
                                        period: 15,
                                        attributes: {
                                          display_max: 1000
                                        }
            foo = Metrics.get_metric :foo
            expect(foo['display_name']).to eq('Foo Metric')
            expect(foo['period']).to eq(15)
            expect(foo['attributes']['display_max']).to eq(1000)
          end
        end

        context "without an existing metric" do
          it "creates the metric if type specified" do
            delete_all_metrics
            Metrics.update_metric :foo, display_name: "Foo Metric",
                                        type: 'gauge',
                                        period: 15,
                                        attributes: {
                                        display_max: 1000
                                      }
            foo = Metrics.get_metric :foo
            expect(foo['display_name']).to eq('Foo Metric')
            expect(foo['period']).to eq(15)
            expect(foo['attributes']['display_max']).to eq(1000)
          end
        end

      end

      context 'with multiple metrics' do
        before do
          delete_all_metrics
          Metrics.submit 'my.1' => 1, 'my.2' => 2, 'my.3' => 3, 'my.4' => 4
        end

        it "supports named list" do
          names = ['my.1', 'my.3']
          Metrics.update_metrics names: names, period: 60

          names.each do |name|
             metric = Metrics.get_metric name
             expect(metric['period']).to eq(60)
           end
        end

        it "supports patterns" do
          Metrics.update_metrics names: 'my.*', exclude: ['my.3'],
            display_max: 100

          %w{my.1 my.2 my.4}.each do |name|
            metric = Metrics.get_metric name
            expect(metric['attributes']['display_max']).to eq(100)
          end

          excluded = Metrics.get_metric 'my.3'
          expect(excluded['attributes']['display_max']).not_to eq(100)
        end
      end
    end

    describe "#get_series" do
      before { Metrics.submit test_series: { value: 123, tags: { hostname: "metrics-web-stg-1" } } }

      context "with a set tag value" do
        it "gets series" do
          series = Metrics.get_series :test_series, resolution: 1, duration: 3600

          expect(series[0]["tags"]["hostname"]).to eq("metrics-web-stg-1")
          expect(series[0]["measurements"][0]["value"]).to eq(123)
        end
      end

      context "with a start_time" do
        it "returns entries since that time" do
          # 1 hr ago
          series = Metrics.get_series :test_series, start_time: Time.now-60
          expect(series[0]['measurements'].length).to eq(1)
        end
      end
    end
  end
end
