# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductItemFilters::DestroyService do
  subject(:result) { described_class.call(product_item_filter:) }

  let(:organization) { create(:organization) }
  let(:product_item_filter) { create(:product_item_filter, :with_values, organization:) }

  it "soft deletes the filter and its values" do
    value_ids = product_item_filter.values.ids
    expect(result).to be_success
    expect(product_item_filter.reload).to be_discarded
    expect(ProductItemFilterValue.with_discarded.where(id: value_ids).map(&:discarded?)).to all(be(true))
  end

  it "produces an activity log" do
    result
    expect(Utils::ActivityLog).to have_produced("product_item_filter.deleted").after_commit.with(product_item_filter)
  end

  context "when product_item_filter is nil" do
    let(:product_item_filter) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_item_filter")
    end
  end
end
