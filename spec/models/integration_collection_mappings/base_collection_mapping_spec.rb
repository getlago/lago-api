# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCollectionMappings::BaseCollectionMapping do
  subject(:mapping) { build(:netsuite_collection_mapping, settings: {}) }

  let(:mapping_types) do
    %i[fallback_item coupon subscription_fee minimum_commitment tax prepaid_credit credit_note account]
  end

  it_behaves_like "paper_trail traceable"

  it { is_expected.to belong_to(:integration) }
  it { is_expected.to belong_to(:organization) }

  it { is_expected.to define_enum_for(:mapping_type).with_values(mapping_types) }

  describe "validations" do
    describe "of mapping type uniqueness" do
      let(:errors) { mapping.errors }
      let(:mapping_type) { :fallback_item }
      let(:type) { "IntegrationCollectionMappings::NetsuiteCollectionMapping" }

      context "when it is unique in scope of integration" do
        it "does not add an error" do
          expect(errors.where(:mapping_type, :taken)).not_to be_present
        end
      end

      context "when it is not unique in scope of integration" do
        subject(:mapping) do
          described_class.new(integration:, type:, mapping_type:, organization: integration.organization)
        end

        let(:integration) { create(:netsuite_integration) }

        before do
          described_class.create(integration:, type:, mapping_type:, organization: integration.organization)
          mapping.valid?
        end

        it "adds an error" do
          expect(errors.where(:mapping_type, :taken)).to be_present
        end
      end
    end
  end

  describe "#push_to_settings" do
    it "push the value into settings" do
      mapping.push_to_settings(key: "key1", value: "val1")

      expect(mapping.settings).to eq(
        {
          "key1" => "val1"
        }
      )
    end
  end

  describe "#get_from_settings" do
    before { mapping.push_to_settings(key: "key1", value: "val1") }

    it { expect(mapping.get_from_settings("key1")).to eq("val1") }

    it { expect(mapping.get_from_settings(nil)).to be_nil }
    it { expect(mapping.get_from_settings("foo")).to be_nil }
  end
end
