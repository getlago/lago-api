# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::ProductCategoryItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:category) { create(:product_category, organization: sandbox, code: "compute") }

  it "answers its item type and activity type" do
    expect(item.item_type).to eq("product_category")
    expect(item.activity_type).to eq("product_category.copied_to_production")
  end

  describe "#find_source" do
    it "finds a category of the sandbox" do
      expect(item.find_source(category.id)).to eq(category)
    end

    it "ignores a category of production" do
      expect(item.find_source(create(:product_category, organization: production).id)).to be_nil
    end
  end

  describe "#find_existing" do
    let(:live_category) { create(:product_category, organization: production, code: "compute") }

    before { live_category }

    it "finds the kept production category with the same code" do
      expect(item.find_existing(category)).to eq(live_category)
    end

    context "when the production category is deleted" do
      before { live_category.discard! }

      it "finds nothing" do
        expect(item.find_existing(category)).to be_nil
      end
    end
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
