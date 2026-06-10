# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::CreateService do
  subject(:result) { described_class.call(organization:, params:) }

  let(:organization) { create(:organization) }
  let(:params) do
    {
      name: "Cards",
      code: "cards",
      description: "Card products",
      invoice_display_name: "Cards"
    }
  end

  it "creates a product" do
    expect { result }.to change(Product, :count).by(1)

    product = result.product
    expect(product.organization).to eq(organization)
    expect(product.name).to eq("Cards")
    expect(product.code).to eq("cards")
    expect(product.description).to eq("Card products")
    expect(product.invoice_display_name).to eq("Cards")
  end

  it "produces an activity log" do
    product = result.product
    expect(Utils::ActivityLog).to have_produced("product.created").after_commit.with(product)
  end

  context "when organization is nil" do
    let(:organization) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("organization")
    end
  end

  context "when the code is already used" do
    before { create(:product, organization:, code: "cards") }

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
