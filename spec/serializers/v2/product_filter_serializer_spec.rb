# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::ProductFilterSerializer do
  subject(:serialized_filter) { described_class.new(product_filter).serialize }

  let(:organization) { create(:organization) }
  let(:category) { create(:product_category, organization:, code: "category-one") }
  let(:product) { create(:product, organization:, product_category: category, code: "product-one") }
  let(:product_filter) { create(:product_filter, organization:, product:) }
  let(:billable_metric_filter) { create(:billable_metric_filter, organization:, billable_metric: product.billable_metric, key: "region", values: %w[us eu]) }
  let(:filter_value) { create(:product_filter_value, organization:, product_filter:, billable_metric_filter:, value: "us") }

  it "serializes the owning product and category codes" do
    expect(serialized_filter).to include(product_code: "product-one", product_category_code: "category-one")
  end

  context "when another filter belongs to a different product and category" do
    let(:other_category) { create(:product_category, organization:, code: "category-two") }
    let(:other_product) { create(:product, organization:, product_category: other_category, code: "product-two") }
    let(:other_filter) { create(:product_filter, organization:, product: other_product) }

    it "serializes each filter with its own parent codes" do
      expect(described_class.new(other_filter).serialize).to include(product_code: "product-two", product_category_code: "category-two")
      expect(serialized_filter).to include(product_code: "product-one", product_category_code: "category-one")
    end
  end

  context "when the product and category are discarded" do
    before do
      product.discard!
      category.discard!
    end

    it "retains their codes" do
      expect(serialized_filter).to include(product_code: "product-one", product_category_code: "category-one")
    end
  end

  context "when the filter is discarded" do
    before do
      filter_value
      product_filter.discard!
    end

    it "serializes no values even when the filter has a kept value" do
      expect(filter_value).not_to be_discarded
      expect(serialized_filter.fetch(:values)).to eq([])
    end
  end
end
