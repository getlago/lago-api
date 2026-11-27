# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::CopyToProduction::ItemTypeEnum do
  it "enumerates the item types a user can copy on their own" do
    expect(described_class.values.keys).to eq(%w[billable_metric catalog_plan coupon feature plan_rate_card product product_category])
  end
end
