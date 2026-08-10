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

  it "does not change the code" do
    expect { result }.not_to change { product_category.reload.code }
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
