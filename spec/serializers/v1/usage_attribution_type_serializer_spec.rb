# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::UsageAttributionTypeSerializer do
  subject(:serializer) { described_class.new(usage_attribution_type, root_name: "usage_attribution_type") }

  let(:parent) { create(:usage_attribution_type, code: "department") }
  let(:usage_attribution_type) { create(:usage_attribution_type, organization: parent.organization, parent:) }

  let(:result) { JSON.parse(serializer.to_json) }

  it "serializes the object" do
    expect(result["usage_attribution_type"]).to eq(
      {
        "lago_id" => usage_attribution_type.id,
        "lago_organization_id" => usage_attribution_type.organization_id,
        "code" => usage_attribution_type.code,
        "name" => usage_attribution_type.name,
        "attribution_keys" => usage_attribution_type.attribution_keys,
        "role" => "hierarchical",
        "lago_parent_id" => parent.id,
        "parent_code" => "department",
        "created_at" => usage_attribution_type.created_at.iso8601,
        "updated_at" => usage_attribution_type.updated_at.iso8601
      }
    )
  end

  context "without a parent" do
    let(:usage_attribution_type) { create(:usage_attribution_type) }

    it "serializes the parent fields as null" do
      expect(result["usage_attribution_type"]["lago_parent_id"]).to be_nil
      expect(result["usage_attribution_type"]["parent_code"]).to be_nil
    end
  end
end
