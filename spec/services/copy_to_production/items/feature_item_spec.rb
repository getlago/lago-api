# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::FeatureItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }

  it_behaves_like "a copy to production item matched by code", :feature
  it_behaves_like "a copy to production item copying every column", Entitlement::Feature
  it_behaves_like "a copy to production item copying every column", Entitlement::Privilege,
    attributes: described_class::PRIVILEGE_ATTRIBUTES, left_out: %w[entitlement_feature_id]

  it "answers its item type and activity type" do
    expect(item.item_type).to eq("feature")
    expect(item.activity_type).to eq("feature.copied_to_production")
  end
end
