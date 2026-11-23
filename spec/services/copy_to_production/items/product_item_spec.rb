# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::ProductItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:category) { create(:product_category, organization: sandbox) }
  let(:metric) { create(:billable_metric, organization: sandbox) }
  let(:product) { create(:product, organization: sandbox, product_category: category, billable_metric: metric, code: "api") }

  it "answers its item type and activity type" do
    expect(item.item_type).to eq("product")
    expect(item.activity_type).to eq("product.copied_to_production")
  end

  describe "#find_source" do
    it "finds a product of the sandbox" do
      expect(item.find_source(product.id)).to eq(product)
    end

    it "ignores a product of production" do
      expect(item.find_source(create(:product, organization: production).id)).to be_nil
    end
  end

  describe "#find_existing" do
    let(:live_category) { create(:product_category, organization: production, code: category.code) }
    let(:live_product) { create(:product, organization: production, product_category: live_category, code: "api") }

    before { live_product }

    it "finds the kept production product with the same code in the live category" do
      expect(item.find_existing(product)).to eq(live_product)
    end

    context "when the production product is in another category" do
      let(:live_category) { create(:product_category, organization: production, code: "other") }

      it "finds nothing" do
        expect(item.find_existing(product)).to be_nil
      end
    end

    context "when the production product is deleted" do
      before { live_product.discard! }

      it "finds nothing" do
        expect(item.find_existing(product)).to be_nil
      end
    end
  end

  describe "#dependencies" do
    it "lists its billable metric" do
      expect(item.dependencies(product)).to eq([["billable_metric", metric]])
    end

    context "with a fixed product" do
      let(:product) { create(:product, :fixed, organization: sandbox) }

      it "lists nothing" do
        expect(item.dependencies(product)).to eq([])
      end
    end

    context "when its metric is deleted" do
      before { metric.discard! }

      it "lists nothing" do
        expect(item.dependencies(product.reload)).to eq([])
      end
    end
  end

  describe "#refusal" do
    it "answers nil" do
      expect(item.refusal(product)).to be_nil
    end

    context "when production uses its code" do
      before { create(:product, organization: production, code: "api") }

      it "answers copy_to_production_code_conflict" do
        expect(item.refusal(product)).to eq("copy_to_production_code_conflict")
      end
    end

    context "when its metric is deleted" do
      before { metric.discard! }

      it "answers copy_to_production_target_deleted" do
        expect(item.refusal(product.reload)).to eq("copy_to_production_target_deleted")
      end
    end
  end

  describe "#parent" do
    it "answers its category" do
      expect(item.parent(product)).to eq(["product_category", category])
    end

    context "without a category" do
      let(:product) { create(:product, :standalone, organization: sandbox) }

      it "answers nil" do
        expect(item.parent(product)).to be_nil
      end
    end
  end

  describe "#children" do
    let(:usd) { create(:rate_card, organization: sandbox, product:, code: "api_usd") }
    let(:eur) { create(:rate_card, organization: sandbox, product:, code: "api_eur") }

    before do
      usd
      eur
    end

    it "lists its rate cards by code" do
      expect(item.children(product)).to eq([["rate_card", eur], ["rate_card", usd]])
    end
  end
end
