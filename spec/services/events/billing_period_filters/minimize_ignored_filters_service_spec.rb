# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::BillingPeriodFilters::MinimizeIgnoredFiltersService do
  subject(:service_result) { described_class.call(ignored_filters:) }

  context "when there is no ignored filter" do
    let(:ignored_filters) { [] }

    it "returns an empty list" do
      expect(service_result.ignored_filters).to eq([])
    end
  end

  context "when clauses cannot be reduced" do
    let(:ignored_filters) { [{"size" => ["512"]}, {"steps" => ["25"]}] }

    it "keeps them untouched" do
      expect(service_result.ignored_filters).to eq([{"size" => ["512"]}, {"steps" => ["25"]}])
    end
  end

  describe "normalization" do
    context "when a key has no value" do
      let(:ignored_filters) { [{"size" => [], "steps" => ["75"]}] }

      it "drops the key, as the event stores skip it when building the SQL" do
        expect(service_result.ignored_filters).to eq([{"steps" => ["75"]}])
      end
    end

    context "when a clause has no key left" do
      let(:ignored_filters) { [{}, {"size" => []}, {"steps" => ["25"]}] }

      it "drops the clause, as it would exclude every event" do
        expect(service_result.ignored_filters).to eq([{"steps" => ["25"]}])
      end
    end

    context "when a key holds duplicated values" do
      let(:ignored_filters) { [{"size" => %w[512 512 1024]}] }

      it "deduplicates them" do
        expect(service_result.ignored_filters).to eq([{"size" => %w[512 1024]}])
      end
    end
  end

  describe "absorption" do
    context "with duplicated clauses" do
      let(:ignored_filters) { [{"size" => ["512"]}, {"size" => ["512"]}] }

      it "keeps the first occurrence only" do
        expect(service_result.ignored_filters).to eq([{"size" => ["512"]}])
      end
    end

    context "with a clause constraining more keys than another one" do
      let(:ignored_filters) { [{"size" => ["512"], "steps" => ["25"]}, {"size" => ["512"]}] }

      it "drops the more specific clause" do
        expect(service_result.ignored_filters).to eq([{"size" => ["512"]}])
      end
    end

    context "with a clause allowing more values than another one" do
      let(:ignored_filters) { [{"size" => ["512"], "steps" => ["25"]}, {"size" => %w[512 1024], "steps" => %w[25 50]}] }

      it "drops the narrower clause" do
        expect(service_result.ignored_filters).to eq([{"size" => %w[512 1024], "steps" => %w[25 50]}])
      end
    end

    context "when clauses only partially overlap" do
      let(:ignored_filters) { [{"size" => ["512"], "steps" => ["25"]}, {"size" => ["512"], "steps" => ["50"]}] }

      it "keeps both, merged on the differing key" do
        expect(service_result.ignored_filters).to eq([{"size" => ["512"], "steps" => %w[25 50]}])
      end
    end
  end

  describe "factorization" do
    context "when clauses differ on a single key" do
      let(:ignored_filters) do
        [
          {"model" => ["llama-2"], "size" => ["512"]},
          {"model" => ["llama-3"], "size" => ["512"]},
          {"model" => ["llama-4"], "size" => ["512"]}
        ]
      end

      it "merges them into a single clause" do
        expect(service_result.ignored_filters).to eq([{"model" => %w[llama-2 llama-3 llama-4], "size" => ["512"]}])
      end
    end

    context "when clauses differ on several keys" do
      let(:ignored_filters) do
        %w[512 1024].flat_map do |size|
          %w[25 50].map { |steps| {"size" => [size], "steps" => [steps]} }
        end
      end

      it "merges the full grid into a single clause" do
        expect(service_result.ignored_filters).to eq([{"size" => %w[512 1024], "steps" => %w[25 50]}])
      end
    end

    context "when clauses do not cover the full grid" do
      let(:ignored_filters) do
        [
          {"size" => ["512"], "steps" => ["25"]},
          {"size" => ["512"], "steps" => ["50"]},
          {"size" => ["1024"], "steps" => ["25"]}
        ]
      end

      it "merges what it can and keeps the rest" do
        expect(service_result.ignored_filters).to eq([
          {"size" => %w[512 1024], "steps" => ["25"]},
          {"size" => ["512"], "steps" => ["50"]}
        ])
      end
    end

    context "when clauses do not constrain the same keys" do
      let(:ignored_filters) { [{"size" => ["512"]}, {"steps" => ["25"]}] }

      it "does not merge them" do
        expect(service_result.ignored_filters).to eq([{"size" => ["512"]}, {"steps" => ["25"]}])
      end
    end

    context "when clauses list the same values in a different order" do
      let(:ignored_filters) do
        [
          {"size" => %w[512 1024], "steps" => ["25"]},
          {"size" => %w[1024 512], "steps" => ["50"]}
        ]
      end

      it "still merges them" do
        expect(service_result.ignored_filters).to eq([{"size" => %w[512 1024], "steps" => %w[25 50]}])
      end
    end
  end

  describe "with a charge holding thousands of filters" do
    let(:models) { Array.new(160) { "model-#{it}" } }
    let(:types) { %w[input output cached] }
    let(:zones) { %w[eu us] }

    # Reproduces the shape that broke the ClickHouse `max_query_size` limit in production:
    # a filter per model and type, plus one per model, type and zone.
    let(:ignored_filters) do
      models.flat_map do |model|
        types.flat_map do |type|
          [{"model" => [model], "type" => [type]}] +
            zones.map { {"model" => [model], "type" => [type], "zone" => [it]} }
        end
      end
    end

    it "reduces the whole set to a single clause" do
      expect(ignored_filters.size).to eq(1440)
      expect(service_result.ignored_filters).to eq([{"model" => models, "type" => types}])
    end
  end
end
