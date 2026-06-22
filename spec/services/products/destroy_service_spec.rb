# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::DestroyService do
  subject(:result) { described_class.call(product:) }

  let(:organization) { create(:organization) }
  let(:product) { create(:product, organization:) }

  before do
    next if product.nil?

    create(:product_item, organization:, product:)
    create(:product_item, :fixed, organization:, product:)
  end

  it "soft deletes the product and its items" do
    item_ids = product.product_items.ids

    expect(result).to be_success
    expect(product.reload).to be_discarded
    expect(ProductItem.with_discarded.where(id: item_ids).map(&:discarded?)).to all(be(true))
  end

  it "produces an activity log for the product and each item" do
    result
    expect(Utils::ActivityLog).to have_produced("product.deleted").after_commit.with(product)
    expect(Utils::ActivityLog).to have_produced("product_item.deleted").after_commit.with(ProductItem.with_discarded.where(product_id: product.id).first)
  end

  context "when product is nil" do
    let(:product) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product")
    end
  end

  context "when the product is attached to a plan" do
    before do
      item = create(:product_item, organization:, product:)
      rate_card = create(:rate_card, organization:, product_item: item)
      create(:plan_rate_card, organization:, rate_card:)
    end

    it "returns a validation failure and discards nothing" do
      expect(result).not_to be_success
      expect(result.error.messages[:product_item]).to eq(["attached_to_plan_or_subscription"])
      expect(product.reload).not_to be_discarded
    end
  end

  context "when the product itself is attached to a plan" do
    before { create(:plan_product, organization:, product:) }

    it "returns a validation failure and discards nothing" do
      expect(result).not_to be_success
      expect(result.error.messages[:product]).to eq(["attached_to_plan_or_subscription"])
      expect(product.reload).not_to be_discarded
    end
  end
end
