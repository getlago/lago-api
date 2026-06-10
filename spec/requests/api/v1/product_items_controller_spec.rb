# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::ProductItemsController do
  let(:organization) { create(:organization) }

  describe "POST /api/v1/product_items" do
    subject { post_with_token(organization, "/api/v1/product_items", {product_item: create_params}) }

    let(:product) { create(:product, organization:) }
    let(:billable_metric) { create(:billable_metric, organization:) }

    let(:create_params) do
      {
        name: "Storage",
        code: "storage",
        item_type: "usage",
        product_id: product.id,
        billable_metric_id: billable_metric.id
      }
    end

    include_examples "requires API permission", "product_item", "write"

    it "creates a product item" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:product_item][:lago_id]).to be_present
      expect(json[:product_item][:name]).to eq("Storage")
      expect(json[:product_item][:code]).to eq("storage")
      expect(json[:product_item][:item_type]).to eq("usage")
      expect(json[:product_item][:lago_product_id]).to eq(product.id)
      expect(json[:product_item][:lago_billable_metric_id]).to eq(billable_metric.id)
    end

    context "with a standalone fixed item" do
      let(:create_params) { {name: "Seats", code: "seats", item_type: "fixed"} }

      it "creates the item without product nor metric" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:product_item][:item_type]).to eq("fixed")
        expect(json[:product_item][:lago_product_id]).to be_nil
        expect(json[:product_item][:lago_billable_metric_id]).to be_nil
      end
    end

    context "when the billable metric belongs to another organization" do
      let(:billable_metric) { create(:billable_metric) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("billable_metric")
      end
    end
  end

  describe "PUT /api/v1/product_items/:id" do
    subject { put_with_token(organization, "/api/v1/product_items/#{product_item.id}", {product_item: update_params}) }

    let(:product_item) { create(:product_item, organization:, name: "Before") }
    let(:update_params) { {name: "After"} }

    include_examples "requires API permission", "product_item", "write"

    it "updates the product item" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:product_item][:name]).to eq("After")
      expect(json[:product_item][:code]).to eq(product_item.code)
    end

    context "when the product item does not exist" do
      subject { put_with_token(organization, "/api/v1/product_items/#{SecureRandom.uuid}", {product_item: update_params}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product_item")
      end
    end
  end

  describe "GET /api/v1/product_items/:id" do
    subject { get_with_token(organization, "/api/v1/product_items/#{product_item.id}") }

    let(:product_item) { create(:product_item, organization:) }

    include_examples "requires API permission", "product_item", "read"

    it "returns the product item" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:product_item][:lago_id]).to eq(product_item.id)
      expect(json[:product_item][:code]).to eq(product_item.code)
    end

    context "when the product item belongs to another organization" do
      let(:product_item) { create(:product_item) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product_item")
      end
    end
  end

  describe "GET /api/v1/product_items" do
    subject { get_with_token(organization, "/api/v1/product_items#{query_params}") }

    let(:query_params) { "" }
    let(:product) { create(:product, organization:) }
    let!(:usage_item) { create(:product_item, organization:, product:) }
    let!(:fixed_item) { create(:product_item, :fixed, :standalone, organization:) }

    include_examples "requires API permission", "product_item", "read"

    it "returns the product items" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:product_items].map { it[:lago_id] }).to match_array([usage_item.id, fixed_item.id])
      expect(json[:meta][:total_count]).to eq(2)
    end

    context "with an item_type filter" do
      let(:query_params) { "?item_type=fixed" }

      it "returns only matching items" do
        subject

        expect(json[:product_items].map { it[:lago_id] }).to eq([fixed_item.id])
      end
    end

    context "with a product_id filter" do
      let(:query_params) { "?product_id=#{product.id}" }

      it "returns only the items of that product" do
        subject

        expect(json[:product_items].map { it[:lago_id] }).to eq([usage_item.id])
      end
    end
  end

  describe "DELETE /api/v1/product_items/:id" do
    subject { delete_with_token(organization, "/api/v1/product_items/#{product_item.id}") }

    let(:product_item) { create(:product_item, organization:) }

    include_examples "requires API permission", "product_item", "write"

    it "soft deletes the product item" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:product_item][:lago_id]).to eq(product_item.id)
      expect(product_item.reload).to be_discarded
    end

    context "when the product item does not exist" do
      subject { delete_with_token(organization, "/api/v1/product_items/#{SecureRandom.uuid}") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product_item")
      end
    end
  end
end
