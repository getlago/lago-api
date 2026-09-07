# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductCategories::DestroyService do
  subject(:result) { described_class.call(product_category:) }

  let(:organization) { create(:organization) }
  let(:product_category) { create(:product_category, organization:) }

  before do
    next if product_category.nil?

    create(:product, organization:, product_category:)
    create(:product, :fixed, organization:, product_category:)
  end

  it "soft deletes the product_category and its items" do
    item_ids = product_category.products.ids

    expect(result).to be_success
    expect(product_category.reload).to be_discarded
    expect(Product.with_discarded.where(id: item_ids).map(&:discarded?)).to all(be(true))
  end

  it "produces an activity log for the product_category and each item" do
    result
    expect(Utils::ActivityLog).to have_produced("product_category.deleted").after_commit.with(product_category)
    expect(Utils::ActivityLog).to have_produced("product.deleted").after_commit.with(Product.with_discarded.where(product_category_id: product_category.id).first)
  end

  context "when product_category is nil" do
    let(:product_category) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_category")
    end
  end

  context "when one of the product_category's items is priced on a plan" do
    before do
      item = create(:product, organization:, product_category:)
      rate_card = create(:rate_card, organization:, product: item)
      create(:plan_rate_card, organization:, rate_card:)
    end

    it "returns a validation failure and discards nothing" do
      expect(result).not_to be_success
      expect(result.error.messages[:product_category]).to eq(["attached_to_plan_or_subscription"])
      expect(product_category.reload).not_to be_discarded
    end
  end
end
