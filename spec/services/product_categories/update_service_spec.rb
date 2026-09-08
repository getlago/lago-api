# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductCategories::UpdateService do
  subject(:result) { described_class.call(product_category:, params:) }

  let(:organization) { create(:organization) }
  let(:product_category) { create(:product_category, organization:, name: "Before", code: "before") }

  let(:params) { {name: "After", description: "new", invoice_display_name: "Display"} }

  it "updates the mutable attributes" do
    expect(result).to be_success
    expect(result.product_category.name).to eq("After")
    expect(result.product_category.description).to eq("new")
    expect(result.product_category.invoice_display_name).to eq("Display")
  end

  describe "code editability" do
    let(:params) { {code: "after"} }

    it "updates the code when the product_category is not in a plan or subscription" do
      expect { result }.to change { product_category.reload.code }.to("after")
    end

    context "when the product_category is attached to a plan" do
      before do
        item = create(:product, organization:, product_category:)
        rate_card = create(:rate_card, organization:, product: item)
        create(:plan_rate_card, organization:, rate_card:)
      end

      it "rejects the code change" do
        expect(result).not_to be_success
        expect(result.error.messages[:code]).to eq(["attached_to_plan_or_subscription"])
        expect(product_category.reload.code).to eq("before")
      end

      it "accepts an unchanged code alongside other updates" do
        update_result = described_class.call(product_category:, params: {code: "before", name: "renamed"})

        expect(update_result).to be_success
        expect(product_category.reload.name).to eq("renamed")
      end
    end
  end

  it "produces an activity log" do
    result
    expect(Utils::ActivityLog).to have_produced("product_category.updated").after_commit.with(product_category)
  end

  context "when product_category is nil" do
    let(:product_category) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_category")
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
