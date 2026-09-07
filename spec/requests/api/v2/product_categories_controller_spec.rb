# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::ProductCategoriesController do
  let(:organization) { create(:organization) }

  describe "POST /api/v2/product_categories" do
    subject { post_with_token(organization, "/api/v2/product_categories", {product_category: create_params}) }

    let(:create_params) do
      {
        name: "Cards",
        code: "cards",
        description: "Card product_categories",
        invoice_display_name: "Cards"
      }
    end

    include_examples "requires API permission", "product_category", "write"

    it "creates a product_category" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:product_category][:lago_id]).to be_present
      expect(json[:product_category][:name]).to eq("Cards")
      expect(json[:product_category][:code]).to eq("cards")
      expect(json[:product_category][:description]).to eq("Card product_categories")
      expect(json[:product_category][:invoice_display_name]).to eq("Cards")
    end

    context "when the code is already used" do
      before { create(:product_category, organization:, code: "cards") }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PUT /api/v2/product_categories/:code" do
    subject { put_with_token(organization, "/api/v2/product_categories/#{product_category.code}", {product_category: update_params}) }

    let(:product_category) { create(:product_category, organization:, name: "Before") }
    let(:update_params) { {name: "After"} }

    include_examples "requires API permission", "product_category", "write"

    it "updates the product_category" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:product_category][:name]).to eq("After")
      expect(json[:product_category][:code]).to eq(product_category.code)
    end

    context "with a code change" do
      let(:update_params) { {code: "after"} }

      it "updates the code when the product_category is not in a plan or subscription" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:product_category][:code]).to eq("after")
      end

      context "when the product_category is attached to a plan" do
        before do
          item = create(:product, organization:, product_category:)
          rate_card = create(:rate_card, organization:, product: item)
          create(:plan_rate_card, organization:, rate_card:)
        end

        it "returns a validation error" do
          subject

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json[:error_details][:code]).to eq(%w[attached_to_plan_or_subscription])
        end
      end
    end

    context "when the product_category does not exist" do
      subject { put_with_token(organization, "/api/v2/product_categories/unknown", {product_category: update_params}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product_category")
      end
    end
  end

  describe "GET /api/v2/product_categories/:code" do
    subject { get_with_token(organization, "/api/v2/product_categories/#{product_category.code}") }

    let(:product_category) { create(:product_category, organization:) }

    include_examples "requires API permission", "product_category", "read"

    it "returns the product_category" do
      create(:product, organization:, product_category:)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:product_category][:lago_id]).to eq(product_category.id)
      expect(json[:product_category][:code]).to eq(product_category.code)
      expect(json[:product_category][:products_count]).to eq(1)
    end

    context "when the product_category does not exist" do
      subject { get_with_token(organization, "/api/v2/product_categories/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product_category")
      end
    end

    context "when the product_category belongs to another organization" do
      let(:product_category) { create(:product_category) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product_category")
      end
    end
  end

  describe "GET /api/v2/product_categories" do
    subject { get_with_token(organization, "/api/v2/product_categories?page=1&per_page=1") }

    before { create(:product_category, organization:) }

    include_examples "requires API permission", "product_category", "read"

    it "returns the paginated product_categories" do
      create(:product_category, organization:)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:product_categories].count).to eq(1)
      expect(json[:meta][:total_count]).to eq(2)
      expect(json[:product_categories].first[:lago_id]).to be_present
    end

    it "returns the batched products counts" do
      product_category = create(:product_category, organization:)
      create(:product, organization:, product_category:)

      get_with_token(organization, "/api/v2/product_categories?per_page=10")

      counts = json[:product_categories].to_h { [it[:lago_id], it[:products_count]] }
      expect(counts[product_category.id]).to eq(1)
    end

    it "does not return product_categories from other organizations" do
      other = create(:product_category)

      subject

      expect(json[:product_categories].map { it[:lago_id] }).not_to include(other.id)
    end

    context "with a search term" do
      subject { get_with_token(organization, "/api/v2/product_categories?search_term=#{search_term}") }

      let(:search_term) { "matching" }
      let(:matching) { create(:product_category, organization:, name: "matching product_category") }
      let(:other) { create(:product_category, organization:, name: "other product_category") }

      before do
        matching
        other
      end

      it "returns only the product_categories matching the search term" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:product_categories].map { it[:lago_id] }).to eq([matching.id])
      end
    end
  end

  describe "DELETE /api/v2/product_categories/:code" do
    subject { delete_with_token(organization, "/api/v2/product_categories/#{product_category.code}") }

    let(:product_category) { create(:product_category, organization:) }

    include_examples "requires API permission", "product_category", "write"

    it "soft deletes the product_category" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:product_category][:lago_id]).to eq(product_category.id)
      expect(product_category.reload).to be_discarded
    end

    context "when the product_category does not exist" do
      subject { delete_with_token(organization, "/api/v2/product_categories/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product_category")
      end
    end
  end
end
