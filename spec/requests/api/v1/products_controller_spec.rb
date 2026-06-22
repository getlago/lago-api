# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::ProductsController do
  let(:organization) { create(:organization) }

  describe "POST /api/v1/products" do
    subject { post_with_token(organization, "/api/v1/products", {product: create_params}) }

    let(:create_params) do
      {
        name: "Cards",
        code: "cards",
        description: "Card products",
        invoice_display_name: "Cards"
      }
    end

    include_examples "requires API permission", "product", "write"

    it "creates a product" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:product][:lago_id]).to be_present
      expect(json[:product][:name]).to eq("Cards")
      expect(json[:product][:code]).to eq("cards")
      expect(json[:product][:description]).to eq("Card products")
      expect(json[:product][:invoice_display_name]).to eq("Cards")
    end

    context "when the code is already used" do
      before { create(:product, organization:, code: "cards") }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PUT /api/v1/products/:code" do
    subject { put_with_token(organization, "/api/v1/products/#{product.code}", {product: update_params}) }

    let(:product) { create(:product, organization:, name: "Before") }
    let(:update_params) { {name: "After"} }

    include_examples "requires API permission", "product", "write"

    it "updates the product" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:product][:name]).to eq("After")
      expect(json[:product][:code]).to eq(product.code)
    end

    context "when the product does not exist" do
      subject { put_with_token(organization, "/api/v1/products/unknown", {product: update_params}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product")
      end
    end
  end

  describe "GET /api/v1/products/:code" do
    subject { get_with_token(organization, "/api/v1/products/#{product.code}") }

    let(:product) { create(:product, organization:) }

    include_examples "requires API permission", "product", "read"

    it "returns the product" do
      create(:product_item, organization:, product:)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:product][:lago_id]).to eq(product.id)
      expect(json[:product][:code]).to eq(product.code)
      expect(json[:product][:product_items_count]).to eq(1)
    end

    context "when the product does not exist" do
      subject { get_with_token(organization, "/api/v1/products/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product")
      end
    end

    context "when the product belongs to another organization" do
      let(:product) { create(:product) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product")
      end
    end
  end

  describe "GET /api/v1/products" do
    subject { get_with_token(organization, "/api/v1/products?page=1&per_page=1") }

    before { create(:product, organization:) }

    include_examples "requires API permission", "product", "read"

    it "returns the paginated products" do
      create(:product, organization:)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:products].count).to eq(1)
      expect(json[:meta][:total_count]).to eq(2)
      expect(json[:products].first[:lago_id]).to be_present
    end

    it "does not return products from other organizations" do
      other = create(:product)

      subject

      expect(json[:products].map { it[:lago_id] }).not_to include(other.id)
    end

    context "with a search term" do
      subject { get_with_token(organization, "/api/v1/products?search_term=#{search_term}") }

      let(:search_term) { "matching" }
      let(:matching) { create(:product, organization:, name: "matching product") }
      let(:other) { create(:product, organization:, name: "other product") }

      before do
        matching
        other
      end

      it "returns only the products matching the search term" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:products].map { it[:lago_id] }).to eq([matching.id])
      end
    end
  end

  describe "DELETE /api/v1/products/:code" do
    subject { delete_with_token(organization, "/api/v1/products/#{product.code}") }

    let(:product) { create(:product, organization:) }

    include_examples "requires API permission", "product", "write"

    it "soft deletes the product" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:product][:lago_id]).to eq(product.id)
      expect(product.reload).to be_discarded
    end

    context "when the product does not exist" do
      subject { delete_with_token(organization, "/api/v1/products/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product")
      end
    end
  end
end
