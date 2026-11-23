# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::CopyToProduction::BlockingReasonEnum do
  it "enumerates the blocking reasons" do
    expect(described_class.values.keys).to eq(
      %w[value_already_exist organization_inactive copy_to_production_admin_only copy_to_production_parent_missing
        copy_to_production_item_unsupported]
    )
  end
end
