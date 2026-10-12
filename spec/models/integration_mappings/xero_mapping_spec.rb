# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationMappings::XeroMapping do
  subject(:mapping) { build(:xero_mapping) }

  describe "validations" do
    context "when the mappable is a tax" do
      subject(:mapping) { build(:xero_mapping, integration:, mappable: tax, organization:) }

      let(:organization) { create(:organization) }
      let(:integration) { create(:xero_integration, organization:) }
      let(:tax) { create(:tax, organization:) }

      it { is_expected.to be_valid }
    end
  end

  describe "#external_id" do
    let(:external_id) { SecureRandom.uuid }

    it "assigns and retrieve a setting" do
      mapping.external_id = external_id
      expect(mapping.external_id).to eq(external_id)
    end
  end

  describe "#external_account_code" do
    let(:external_account_code) { "xero-code-1" }

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
end
