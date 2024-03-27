# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::GroupSerializer do
  subject(:serializer) { described_class.new(group, root_name: "group") }

  let(:group) { create(:group) }

  it "serializes the object" do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result["group"]["lago_id"]).to eq(group.id)
      expect(result["group"]["key"]).to eq(group.key)
      expect(result["group"]["value"]).to eq(group.value)
    end
  end
end
