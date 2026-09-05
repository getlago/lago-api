# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductCategories::CreateService do
  subject(:result) { described_class.call(organization:, params:) }

  let_it_be(:organization) { create(:organization) }
  let(:params) do
    {
      name: "Cards",
      code: "cards",
      description: "Card product_categories",
      invoice_display_name: "Cards"
    }
  end

  it "creates a product_category" do
    expect { result }.to change(ProductCategory, :count).by(1)

    product_category = result.product_category
    expect(product_category.organization).to eq(organization)
    expect(product_category.name).to eq("Cards")
    expect(product_category.code).to eq("cards")
    expect(product_category.description).to eq("Card product_categories")
    expect(product_category.invoice_display_name).to eq("Cards")
  end

  it "produces an activity log" do
    product_category = result.product_category
    expect(Utils::ActivityLog).to have_produced("product_category.created").after_commit.with(product_category)
  end

  context "when organization is nil" do
    let(:organization) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("organization")
    end
  end

  context "when the code is already used" do
    before { create(:product_category, organization:, code: "cards") }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:code]).to be_present
    end
  end

  context "when name is missing" do
    before { params[:name] = nil }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:name]).to be_present
    end
  end
end
