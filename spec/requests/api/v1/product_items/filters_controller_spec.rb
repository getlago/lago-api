# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::ProductItems::FiltersController do
  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:product_item) { create(:product_item, organization:, billable_metric:) }
  let(:region_filter) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[us eu]) }

  describe "POST /api/v1/product_items/:product_item_id/filters" do
    subject { post_with_token(organization, "/api/v1/product_items/#{product_item.id}/filters", {filter: create_params}) }

    let(:create_params) do
      {
        name: "US",
        code: "us",
        values: [{billable_metric_filter_id: region_filter.id, value: "us"}]
      }
    end

    include_examples "requires API permission", "product_item", "write"

    it "creates a filter with its values" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:filter][:lago_id]).to be_present
      expect(json[:filter][:name]).to eq("US")
      expect(json[:filter][:code]).to eq("us")
      expect(json[:filter][:values].map { [it[:key], it[:value]] }).to eq([%w[region us]])
    end

    context "when values are missing" do
      let(:create_params) { {name: "US", code: "us", values: []} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when the product item does not exist" do
      subject { post_with_token(organization, "/api/v1/product_items/#{SecureRandom.uuid}/filters", {filter: create_params}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product_item")
      end
    end
  end

  describe "PUT /api/v1/product_items/:product_item_id/filters/:id" do
    subject do
      put_with_token(
        organization,
        "/api/v1/product_items/#{product_item.id}/filters/#{filter.id}",
        {filter: update_params}
      )
    end

    let(:filter) do
      record = create(:product_item_filter, organization:, product_item:, name: "Before")
      create(:product_item_filter_value, organization:, product_item_filter: record, billable_metric_filter: region_filter, value: "us")
      record
    end

    let(:update_params) { {name: "After", values: [{billable_metric_filter_id: region_filter.id, value: "eu"}]} }

    include_examples "requires API permission", "product_item", "write"

    it "updates the filter and replaces its values" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:filter][:name]).to eq("After")
      expect(json[:filter][:values].map { [it[:key], it[:value]] }).to eq([%w[region eu]])
    end

    context "with a code change" do
      let(:update_params) { {code: "after"} }

      it "updates the code when the item is not in a plan or subscription" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:filter][:code]).to eq("after")
        expect(json[:filter][:attached_to_plan_or_subscription]).to be(false)
      end
    end

    context "when the filter does not exist" do
      subject { put_with_token(organization, "/api/v1/product_items/#{product_item.id}/filters/#{SecureRandom.uuid}", {filter: update_params}) }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("product_item_filter")
      end
    end
  end

  describe "GET /api/v1/product_items/:product_item_id/filters/:id" do
    subject { get_with_token(organization, "/api/v1/product_items/#{product_item.id}/filters/#{filter.id}") }

    let(:filter) { create(:product_item_filter, :with_values, organization:, product_item:) }

    include_examples "requires API permission", "product_item", "read"

    it "returns the filter" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:filter][:lago_id]).to eq(filter.id)
      expect(json[:filter][:values].count).to eq(1)
    end
  end

  describe "GET /api/v1/product_items/:product_item_id/filters" do
    subject { get_with_token(organization, "/api/v1/product_items/#{product_item.id}/filters") }

    before do
      create(:product_item_filter, organization:, product_item:)
      create(:product_item_filter, organization:)
    end

    include_examples "requires API permission", "product_item", "read"

    it "returns only the filters of the product item" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:filters].count).to eq(1)
      expect(json[:meta][:total_count]).to eq(1)
    end

    context "with a search term" do
      subject { get_with_token(organization, "/api/v1/product_items/#{product_item.id}/filters?search_term=findme") }

      let!(:matching) { create(:product_item_filter, organization:, product_item:, name: "findme filter") }

      it "returns only the filters matching the search term" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:filters].map { it[:lago_id] }).to eq([matching.id])
      end
    end
  end

  describe "DELETE /api/v1/product_items/:product_item_id/filters/:id" do
    subject { delete_with_token(organization, "/api/v1/product_items/#{product_item.id}/filters/#{filter.id}") }

    let(:filter) { create(:product_item_filter, :with_values, organization:, product_item:) }

    include_examples "requires API permission", "product_item", "write"

    it "soft deletes the filter" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:filter][:lago_id]).to eq(filter.id)
      expect(filter.reload).to be_discarded
    end
  end
end
