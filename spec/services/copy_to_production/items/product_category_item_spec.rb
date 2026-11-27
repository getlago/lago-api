# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::ProductCategoryItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:category) { create(:product_category, organization: sandbox, code: "compute") }

  it_behaves_like "a copy to production item matched by code", :product_category
  it_behaves_like "a copy to production item copying every column", ProductCategory

  it "answers its item type and activity type" do
    expect(item.item_type).to eq("product_category")
    expect(item.activity_type).to eq("product_category.copied_to_production")
  end

  describe "#children" do
    let(:storage) { create(:product, organization: sandbox, product_category: category, code: "storage") }
    let(:api) { create(:product, organization: sandbox, product_category: category, code: "api") }

    before do
      storage
      api
      create(:product, organization: sandbox, product_category: category, code: "legacy", deleted_at: Time.current)
    end

    it "lists its kept products by code" do
      expect(item.children(category)).to eq([["product", api], ["product", storage]])
    end
  end
end
