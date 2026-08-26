# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::DestroyService do
  subject(:result) { described_class.call(product:) }

  let(:organization) { create(:organization) }
  let(:product) { create(:product, :with_filters, organization:) }

  before do
    next if product.nil?

    filter = product.filters.first
    create(
      :product_filter_value,
      organization:,
      product_filter: filter,
      billable_metric_filter: create(:billable_metric_filter, organization:, billable_metric: product.billable_metric, values: %w[us])
    )
    create(:rate_card_rate, organization:, rate_card: create(:rate_card, organization:, product:))
  end

  it "soft deletes the item with its filters, values, rate cards and rates" do
    expect(result).to be_success
    expect(product.reload).to be_discarded
    expect(ProductFilter.with_discarded.where(product_id: product.id).map(&:discarded?)).to all(be(true))
    expect(RateCard.with_discarded.where(product_id: product.id).map(&:discarded?)).to all(be(true))
    expect(
      RateCardRate.with_discarded
        .where(rate_card_id: RateCard.with_discarded.where(product_id: product.id).ids)
        .map(&:discarded?)
    ).to all(be(true))
  end

  it "produces an activity log" do
    result
    expect(Utils::ActivityLog).to have_produced("product.deleted").after_commit.with(product)
  end

  context "when product is nil" do
    let(:product) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product")
    end
  end

  context "when the item is attached to a subscription" do
    before do
      rate_card = create(:rate_card, organization:, product:)
      create(:contract_rate_card, organization:, rate_card:)
    end

    it "returns a validation failure and discards nothing" do
      expect(result).not_to be_success
      expect(result.error.messages[:product]).to eq(["attached_to_plan_or_subscription"])
      expect(product.reload).not_to be_discarded
    end
  end
end
