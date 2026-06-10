# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductItems::DestroyService do
  subject(:result) { described_class.call(product_item:) }

  let(:organization) { create(:organization) }
  let(:product_item) { create(:product_item, :with_filters, organization:) }

  before do
    next if product_item.nil?

    filter = product_item.filters.first
    create(
      :product_item_filter_value,
      organization:,
      product_item_filter: filter,
      billable_metric_filter: create(:billable_metric_filter, organization:, billable_metric: product_item.billable_metric, values: %w[us])
    )
    create(:rate_card_rate, organization:, rate_card: create(:rate_card, organization:, product_item:))
  end

  it "soft deletes the item with its filters, values, rate cards and rates" do
    expect(result).to be_success
    expect(product_item.reload).to be_discarded
    expect(ProductItemFilter.with_discarded.where(product_item_id: product_item.id).map(&:discarded?)).to all(be(true))
    expect(RateCard.with_discarded.where(product_item_id: product_item.id).map(&:discarded?)).to all(be(true))
    expect(
      RateCardRate.with_discarded
        .where(rate_card_id: RateCard.with_discarded.where(product_item_id: product_item.id).ids)
        .map(&:discarded?)
    ).to all(be(true))
  end

  it "produces an activity log" do
    result
    expect(Utils::ActivityLog).to have_produced("product_item.deleted").after_commit.with(product_item)
  end

  context "when product_item is nil" do
    let(:product_item) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_item")
    end
  end
end
