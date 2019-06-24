require "spec_helper"

module AppOptics
  module Metrics
    describe ParamsEncoder do
      let(:single_tag) {
        {
          "resolution" => "3600",
          "duration" => "60",
          "tags" => {
            "hostname" => "app1"
          }
        }
      }

      let(:multi_tag) {
        {
          "resolution" => "3600",
          "duration" => "60",
          "tags" => {
            "hostname" => ['app1', 'app2']
          }
        }
      }
      context "encode" do
        it "single value tag" do
          result = described_class.encode(single_tag)
          expect(result).to eq("resolution=3600&duration=60&tags[hostname]=app1")
        end

        it "array value tag" do
          result = described_class.encode(multi_tag)
          expect(result).to eq("resolution=3600&duration=60&tags[hostname]=app1&tags[hostname]=app2")
        end
      end

      context "decode" do
        it "single value tag" do
          result = described_class.decode("resolution=3600&duration=60&tags[hostname]=app1")
          expect(result).to eq(single_tag)
        end

        it "array value tag" do
          result = described_class.decode("resolution=3600&duration=60&tags[hostname]=app1&tags[hostname]=app2")
          expect(result).to eq(multi_tag)
        end
      end
    end
  end
end
