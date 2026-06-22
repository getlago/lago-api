# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::UpdateService do
  subject(:result) { described_class.call(product:, params:) }

  let(:organization) { create(:organization) }
  let(:product) { create(:product, organization:, name: "Before", code: "before") }

  let(:params) { {name: "After", description: "new", invoice_display_name: "Display"} }

  it "updates the mutable attributes" do
    expect(result).to be_success
    expect(result.product.name).to eq("After")
    expect(result.product.description).to eq("new")
    expect(result.product.invoice_display_name).to eq("Display")
  end

  describe "code editability" do
    let(:params) { {code: "after"} }

    it "updates the code when the product is not in a plan or subscription" do
      expect { result }.to change { product.reload.code }.to("after")
    end

    context "when the product is attached to a plan" do
      before { create(:plan_product, organization:, product:) }

      it "rejects the code change" do
        expect(result).not_to be_success
        expect(result.error.messages[:code]).to eq(["attached_to_plan_or_subscription"])
        expect(product.reload.code).to eq("before")
      end

      it "accepts an unchanged code alongside other updates" do
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
