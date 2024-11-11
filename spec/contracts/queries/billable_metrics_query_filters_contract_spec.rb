# frozen_string_literal: true

require "rails_helper"

RSpec.describe Queries::BillableMetricsQueryFiltersContract, type: :contract do
  subject(:result) { described_class.new.call(filters:, search_term:) }

  let(:filters) { {} }
  let(:search_term) { nil }

  context "when filters are valid" do
    let(:filters) do
      {
        recurring: true,
        aggregation_types: ["max_agg", "count_agg"]
      }
    end

    it "is valid" do
      expect(result.success?).to be(true)
    end
  end

  context "when search_term is provided and valid" do
    let(:search_term) { "valid_search_term" }

    it "is valid" do
      expect(result.success?).to be(true)
    end
  end

  context "when search_term is invalid" do
    let(:search_term) { 12345 }

    it "is invalid" do
      expect(result.success?).to be(false)
      expect(result.errors.to_h).to include(search_term: ["must be a string"])
    end
  end

  context "when filters are invalid" do
    shared_examples "an invalid filter" do |filter, value, error_message|
      let(:filters) { {filter => value} }

      it "is invalid when #{filter} is set to #{value.inspect}" do
        expect(result.success?).to be(false)
        expect(result.errors.to_h).to include(filters: {filter => error_message})
      end
    end

    it_behaves_like "an invalid filter", :recurring, nil, ["must be filled"]
    it_behaves_like "an invalid filter", :recurring, "not_a_bool", ["must be boolean"]

    it_behaves_like "an invalid filter", :aggregation_types, nil, ["must be an array"]
    it_behaves_like "an invalid filter", :aggregation_types, "not_an_array", ["must be an array"]
    it_behaves_like "an invalid filter", :aggregation_types, [1], {0 => ["must be a string"]}
    it_behaves_like "an invalid filter", :aggregation_types, ["invalid_type"], {0 => ["must be one of: max_agg, count_agg"]}
  end
end
