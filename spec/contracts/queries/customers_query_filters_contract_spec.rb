# frozen_string_literal: true

require "rails_helper"

RSpec.describe Queries::CustomersQueryFiltersContract do
  subject(:result) { described_class.new.call(filters:, search_term:) }

  let(:filters) { {} }
  let(:search_term) { nil }

  context "when filtering by account type" do
    let(:filters) { {account_type: %w[customer partner]} }

    it "is valid" do
      expect(result.success?).to be(true)
    end
  end

  context "when filtering by billing entity ids" do
    let(:filters) { {billing_entity_ids: ["123e4567-e89b-12d3-a456-426614174000"]} }

    it "is valid" do
      expect(result.success?).to be(true)
    end
  end

  context "when filtering by currencies" do
    let(:filters) { {currencies: ["USD"]} }

    it "is valid" do
      expect(result.success?).to be(true)
    end
  end

  context "when filtering by countries" do
    let(:filters) { {countries: ["US"]} }

    it "is valid" do
      expect(result.success?).to be(true)
    end
  end

  context "when filtering by states" do
    let(:filters) { {states: ["CA"]} }

    it "is valid" do
      expect(result.success?).to be(true)
    end
  end

  context "when filtering by zipcodes" do
    let(:filters) { {zipcodes: ["10115"]} }

    it "is valid" do
      expect(result.success?).to be(true)
    end
  end

  context "when filtering by has_tax_identification_number" do
    [
      "true",
      "false",
      true,
      false
    ].each do |value|
      let(:filters) { {has_tax_identification_number: value} }

      it "is valid" do
        expect(result.success?).to be(true)
      end
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
        expect(result.errors.to_h).to match(filters: {filter => error_message})
      end
    end

    it_behaves_like "an invalid filter", :account_type, nil, ["must be an array"]
    it_behaves_like "an invalid filter", :account_type, %w[random], {0 => ["must be one of: customer, partner"]}
    it_behaves_like "an invalid filter", :billing_entity_ids, SecureRandom.uuid, ["must be an array"]
    it_behaves_like "an invalid filter", :billing_entity_ids, %w[random], {0 => ["is in invalid format"]}
    it_behaves_like "an invalid filter", :currencies, %w[random], {0 => [/^must be one of: AED,.*ZMW$/]}
    it_behaves_like "an invalid filter", :countries, %w[random], {0 => [/^must be one of: AD, .*XK$/]}
    it_behaves_like "an invalid filter", :states, SecureRandom.uuid, ["must be an array"]
    it_behaves_like "an invalid filter", :zipcodes, SecureRandom.uuid, ["must be an array"]
    it_behaves_like "an invalid filter", :has_tax_identification_number, SecureRandom.uuid, ["must be one of: true, false"]
    it_behaves_like "an invalid filter", :has_tax_identification_number, "t", ["must be one of: true, false"]
    it_behaves_like "an invalid filter", :has_tax_identification_number, "f", ["must be one of: true, false"]
    it_behaves_like "an invalid filter", :has_tax_identification_number, 1, ["must be one of: true, false"]
    it_behaves_like "an invalid filter", :has_tax_identification_number, 0, ["must be one of: true, false"]
  end
end
