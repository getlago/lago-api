# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCollectionMappings::NetsuiteCollectionMapping do
  subject(:mapping) { build(:netsuite_collection_mapping) }

  describe "#external_id" do
    let(:external_id) { SecureRandom.uuid }

    it "assigns and retrieve a setting" do
      mapping.external_id = external_id
      expect(mapping.external_id).to eq(external_id)
    end
  end

  describe "#external_account_code" do
    let(:external_account_code) { "netsuite-code-1" }

    it "assigns and retrieve a setting" do
      mapping.external_account_code = external_account_code
      expect(mapping.external_account_code).to eq(external_account_code)
    end
  end

  describe "#external_name" do
    let(:external_name) { "Credits and Discounts" }

    it "assigns and retrieve a setting" do
      mapping.external_name = external_name
      expect(mapping.external_name).to eq(external_name)
    end
  end

  describe "#tax_nexus" do
    let(:tax_nexus) { "tax-nexus-1" }

    it "assigns and retrieve a setting" do
      mapping.tax_nexus = tax_nexus
      expect(mapping.tax_nexus).to eq(tax_nexus)
    end
  end

  describe "#tax_type" do
    let(:tax_type) { "tax-type-1" }

    it "assigns and retrieve a setting" do
      mapping.tax_type = tax_type
      expect(mapping.tax_type).to eq(tax_type)
    end
  end

  describe "#tax_code" do
    let(:tax_code) { "tax-code-1" }

    it "assigns and retrieve a setting" do
      mapping.tax_code = tax_code
      expect(mapping.tax_code).to eq(tax_code)
    end
  end
end
