# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationMappings::BaseMapping do
  subject(:mapping) { build(:netsuite_mapping, settings: {}) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to belong_to(:integration) }
  it { is_expected.to belong_to(:organization) }

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
