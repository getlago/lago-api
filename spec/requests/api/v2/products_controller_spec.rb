# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::ProductsController do
  let(:organization) { create(:organization) }

  describe "POST /api/v2/products" do
    subject { post_with_token(organization, "/api/v2/products", {product: create_params}) }

    let(:product_category) { create(:product_category, organization:) }
    let(:billable_metric) { create(:billable_metric, organization:) }

    let(:create_params) do
      {
        name: "Storage",
        code: "storage",
        product_type: "usage",
        product_category_code: product_category.code,
        billable_metric_code: billable_metric.code
      }
    end

    include_examples "requires API permission", "product", "write"

    it "creates a product" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:product][:lago_id]).to be_present
      expect(json[:product][:name]).to eq("Storage")
      expect(json[:product][:code]).to eq("storage")
      expect(json[:product][:product_type]).to eq("usage")
      expect(json[:product][:product_category_code]).to eq(product_category.code)
      expect(json[:product][:billable_metric_code]).to eq(billable_metric.code)
    end

    context "with a standalone fixed item" do
      let(:create_params) { {name: "Seats", code: "seats", product_type: "fixed"} }

      it "creates the item without product_category nor metric" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:product][:product_type]).to eq("fixed")
        expect(json[:product][:product_category_code]).to be_nil
        expect(json[:product][:billable_metric_code]).to be_nil
      end
    end

    context "when the billable metric belongs to another organization" do
      let(:billable_metric) { create(:billable_metric) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("billable_metric")
      end
    end

    context "when a usage item has no billable metric" do
      let(:create_params) { {name: "Orphan", code: "orphan", product_type: "usage"} }

      it "returns a validation error naming billable_metric_code" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error_details][:billable_metric_code]).to eq(["value_is_mandatory"])
      end
    end
  end

  describe "PUT /api/v2/products/:id" do
    subject { put_with_token(organization, "/api/v2/products/#{product.code}", {product: update_params}) }

    let(:product) { create(:product, organization:, name: "Before") }
    let(:update_params) { {name: "After"} }

    include_examples "requires API permission", "product", "write"

    it "updates the product" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:product][:name]).to eq("After")
      expect(json[:product][:code]).to eq(product.code)
    end

    context "with a code change" do
      let(:update_params) { {code: "after"} }

      it "updates the code when the item is not in a plan or subscription" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:product][:code]).to eq("after")
      end

      context "when the item is attached to a plan" do
        before do
          rate_card = create(:rate_card, organization:, product:)
          create(:plan_rate_card, organization:, rate_card:)
        end

        it "returns a validation error" do
          subject

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json[:error_details][:code]).to eq(%w[attached_to_plan_or_subscription])
        end
      end
    end

    context "with a product_category_code change" do
      let(:other_product_category) { create(:product_category, organization:) }
      let(:update_params) { {product_category_code: other_product_category.code} }

      it "moves the item to the other product_category" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:product][:product_category_code]).to eq(other_product_category.code)
      end

      context "when the product_category does not exist" do
        let(:update_params) { {product_category_code: "unknown"} }

        it "returns a not found error" do
          subject

          expect(response).to be_not_found_error("product_category")
        end
      end

      context "when the item is attached to a plan" do
        before do
          rate_card = create(:rate_card, organization:, product:)
          create(:plan_rate_card, organization:, rate_card:)
        end

        it "returns a validation error naming product_category_code" do
          subject

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json[:error_details][:product_category_code]).to eq(%w[attached_to_plan_or_subscription])
        end
      end

      context "when the product_category_code is null" do
        let(:product) { create(:product, organization:, product_category: other_product_category) }
        let(:update_params) { {product_category_code: nil} }

        it "detaches the item from its product_category" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:product][:product_category_code]).to be_nil
          expect(product.reload.product_category).to be_nil
        end
      end
    end

    context "when the product does not exist" do
      subject { put_with_token(organization, "/api/v2/products/#{SecureRandom.uuid}", {product: update_params}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product")
      end
    end
  end

  describe "GET /api/v2/products/:id" do
    subject { get_with_token(organization, "/api/v2/products/#{product.code}") }

    let(:product) { create(:product, organization:) }

    include_examples "requires API permission", "product", "read"

    it "returns the product" do
      create(:product_filter, organization:, product:)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:product][:lago_id]).to eq(product.id)
      expect(json[:product][:code]).to eq(product.code)
      expect(json[:product][:filters_count]).to eq(1)
    end

    context "when the product belongs to another organization" do
      let(:product) { create(:product) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product")
      end
    end
  end

  describe "GET /api/v2/products" do
    subject { get_with_token(organization, "/api/v2/products#{query_params}") }

    let(:query_params) { "" }
    let(:product_category) { create(:product_category, organization:) }
    let!(:usage_item) { create(:product, organization:, product_category:) }
    let!(:fixed_item) { create(:product, :fixed, :standalone, organization:) }

    include_examples "requires API permission", "product", "read"

    it "returns the products" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:products].map { it[:lago_id] }).to match_array([usage_item.id, fixed_item.id])
      expect(json[:meta][:total_count]).to eq(2)
    end

    it "returns the batched filters counts" do
      create(:product_filter, organization:, product: usage_item)
      create(:product_filter, organization:, product: usage_item, code: "second")

      subject

      counts = json[:products].to_h { [it[:lago_id], it[:filters_count]] }
      expect(counts).to eq(usage_item.id => 2, fixed_item.id => 0)
    end

    context "with an product_type filter" do
      let(:query_params) { "?product_type=fixed" }

      it "returns only matching items" do
        subject

        expect(json[:products].map { it[:lago_id] }).to eq([fixed_item.id])
      end

      context "when the product_type is not a known type" do
        let(:query_params) { "?product_type=bogus" }

        it "returns a validation error" do
          subject

          expect(response).to have_http_status(:unprocessable_entity)
          expect(json[:error_details][:product_type]).to eq(%w[value_is_invalid])
        end
      end
    end

    context "with a product_category_code filter" do
      let(:query_params) { "?product_category_code=#{product_category.code}" }

      it "returns only the items of that product_category" do
        subject

        expect(json[:products].map { it[:lago_id] }).to eq([usage_item.id])
      end
    end

    context "with multiple product_category_code values" do
      let(:other_product_category) { create(:product_category, organization:) }
      let!(:other_item) { create(:product, organization:, product_category: other_product_category) }
      let(:query_params) { "?product_category_code[]=#{product_category.code}&product_category_code[]=#{other_product_category.code}" }

      it "returns the items of all requested product_categories" do
        subject

        expect(json[:products].map { it[:lago_id] }).to match_array([usage_item.id, other_item.id])
      end
    end

    context "with a without_product_category filter" do
      let(:query_params) { "?without_product_category=true" }

      it "returns only the items not attached to any product_category" do
        subject

        expect(json[:products].map { it[:lago_id] }).to eq([fixed_item.id])
      end
    end

    context "with product_category_code and without_product_category combined" do
      let(:query_params) { "?product_category_code[]=#{product_category.code}&without_product_category=true" }

      it "returns the union of both" do
        subject

        expect(json[:products].map { it[:lago_id] }).to match_array([usage_item.id, fixed_item.id])
      end
    end

    context "when one of the product_category codes does not exist" do
      let(:query_params) { "?product_category_code[]=#{product_category.code}&product_category_code[]=unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product_category")
      end
    end

    context "with a search term" do
      let(:query_params) { "?search_term=findme" }
      let!(:matching_item) { create(:product, organization:, product_category:, name: "findme item") }

      it "returns only the items matching the search term" do
        subject

        expect(json[:products].map { it[:lago_id] }).to eq([matching_item.id])
      end
    end
  end

  describe "DELETE /api/v2/products/:id" do
    subject { delete_with_token(organization, "/api/v2/products/#{product.code}") }

    let(:product) { create(:product, organization:) }

    include_examples "requires API permission", "product", "write"

    it "soft deletes the product" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:product][:lago_id]).to eq(product.id)
      expect(product.reload).to be_discarded
    end

    context "when the product does not exist" do
      subject { delete_with_token(organization, "/api/v2/products/#{SecureRandom.uuid}") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product")
      end
    end
  end
end
