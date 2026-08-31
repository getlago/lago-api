# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::UpdateService do
  subject(:result) { described_class.call(product:, params:) }

  let_it_be(:organization) { create(:organization) }

  before_all do
    create_default(:billable_metric)
  end

  let(:product) { create(:product, organization:, name: "Before", code: "before") }
  let(:params) { {name: "After", description: "new", invoice_display_name: "Display"} }

  it "updates the mutable attributes" do
    expect(result).to be_success
    expect(result.product.name).to eq("After")
    expect(result.product.description).to eq("new")
    expect(result.product.invoice_display_name).to eq("Display")
  end

  describe "code and product_category editability" do
    let(:other_product_category) { create(:product_category, organization:) }
    let(:params) { {code: "after", product_category_id: other_product_category.id} }

    it "updates the code and product_category attachment when not in a plan or subscription" do
      expect(result).to be_success
      expect(result.product.code).to eq("after")
      expect(result.product.product_category).to eq(other_product_category)
    end

    it "returns a not found failure when the product_category does not exist" do
      result = described_class.call(product:, params: {product_category_id: "unknown"})
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_category")
    end

    context "when the item is attached to a plan" do
      before do
        rate_card = create(:rate_card, organization:, product:)
        create(:plan_rate_card, organization:, rate_card:)
      end

      it "rejects the structural change" do
        expect(result).not_to be_success
        expect(result.error.messages[:code]).to eq(["attached_to_plan_or_subscription"])
        expect(product.reload.code).to eq("before")
      end

      it "accepts unchanged structural fields alongside other updates" do
        update_result = described_class.call(product:, params: {code: "before", name: "renamed"})

        expect(update_result).to be_success
        expect(product.reload.name).to eq("renamed")
      end
    end
  end

  it "produces an activity log" do
    result
    expect(Utils::ActivityLog).to have_produced("product.updated").after_commit.with(product)
  end

  context "when product is nil" do
    let(:product) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product")
    end
  end

  context "when name is blank" do
    let(:params) { {name: ""} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:name]).to be_present
    end
  end
end
