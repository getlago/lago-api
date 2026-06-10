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

  context "when a scoped rate card exists" do
    let(:product_item) { product_item_filter.product_item }
    let!(:scoped_card) { create(:rate_card, organization:, product_item:, product_item_filter:) }

    it "discards the scoped rate card alongside the filter" do
      expect(result).to be_success
      expect(scoped_card.reload).to be_discarded
    end
  end

  context "when the item is attached to a plan" do
    before do
      rate_card = create(:rate_card, organization:, product_item: product_item_filter.product_item)
      create(:plan_rate_card, organization:, rate_card:)
    end

    it "returns a validation failure and discards nothing" do
      expect(result).not_to be_success
      expect(result.error.messages[:product_item_filter]).to eq(["attached_to_plan_or_subscription"])
      expect(product_item_filter.reload).not_to be_discarded
    end
  end

  context "when product_item_filter is nil" do
    let(:product_item_filter) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_item_filter")
    end
  end
end
