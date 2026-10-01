# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::BaseController, type: :controller do
  include ApiHelper

  controller(described_class) do
    # A lookup of the controller's own, declared before the cursor on purpose: the cursor
    # callback belongs to the base controller, so it runs first whatever the order here.
    before_action(only: :index) { not_found_error(resource: "product") if params[:missing] }
    cursor_paginated_index(Product)

    def index
      page = ::CursorPagination::Page.new(records: ::CursorPagination::Keyset.apply(current_organization.products, cursor), cursor:)

      render(json: {products: page.records.map(&:id), meta: page.meta})
    end

    def show
      reject_offset_pagination!
      head(:ok)
    end

    def create
      params.require(:product)
      head(:ok)
    end

    private

    def resource_name
      "product"
    end
  end

  subject(:index) { get(:index, params:) }

  let(:organization) { create(:organization, feature_flags:) }
  let(:feature_flags) { ["product_catalog"] }
  let(:params) { {} }
  let(:products) { create_list(:product, 3, organization:).sort_by { [it.created_at, it.id] }.reverse }
  let(:errors_counter) { Yabeda.api_pagination.errors_total }

  before do
    # A controller spec has no `get_with_token`: the helper's headers are set on the test request.
    products
    set_headers(organization, request.headers)
    allow(errors_counter).to receive(:increment)
  end

  context "with a limit" do
    let(:params) { {limit: "2"} }

    it "returns the page and its cursors" do
      index

      expect(json[:products]).to eq(products.first(2).map(&:id))
      expect(json[:meta]).to eq(
        next_cursor: CursorPagination::Token.encode(table: "products", record: products[1]),
        prev_cursor: nil
      )
    end
  end

  context "with an invalid limit" do
    let(:params) { {limit: "101"} }

    it "returns a bad request error keyed by the parameter" do
      index

      expect(response).to have_http_status(:bad_request)
      expect(json).to eq(
        status: 400,
        error: "Bad Request",
        code: "invalid_pagination_limit",
        error_details: {limit: {value: "101", allowed_range: "1..100"}}
      )
    end

    it "counts the error by code" do
      index

      expect(errors_counter).to have_received(:increment).with({code: "invalid_pagination_limit"})
    end
  end

  context "with an invalid limit and a failing lookup" do
    let(:params) { {limit: "0", missing: "true"} }

    it "rejects the pagination parameters before the lookup" do
      index

      expect(response).to have_http_status(:bad_request)
      expect(json[:code]).to eq("invalid_pagination_limit")
    end
  end

  context "when the organization is not on the product catalog" do
    let(:feature_flags) { [] }
    let(:params) { {limit: "0"} }

    it "checks the catalog before reading the cursor" do
      index

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("feature_unavailable")
    end
  end

  context "without a valid API key" do
    let(:params) { {limit: "0"} }

    before { request.headers["Authorization"] = "Bearer invalid" }

    it "authenticates before reading the cursor" do
      index

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "with an invalid cursor" do
    let(:params) { {after: "a"} }

    it "returns a bad request error" do
      index

      expect(response).to have_http_status(:bad_request)
      expect(json[:code]).to eq("invalid_pagination_cursor")
      expect(json[:error_details]).to eq(after: {reason: "malformed"})
    end
  end

  context "with offset pagination parameters" do
    let(:params) { {page: "2", per_page: "50"} }

    it "returns a bad request error" do
      index

      expect(response).to have_http_status(:bad_request)
      expect(json[:code]).to eq("invalid_pagination_parameter")
      expect(json[:error_details]).to eq(page: {reason: "replaced_by_cursor"}, per_page: {reason: "replaced_by_cursor"})
    end
  end

  context "with include_total_count on a later page" do
    let(:params) { {include_total_count: "true", after: CursorPagination::Token.encode(table: "products", record: products[0])} }

    it "returns a bad request error" do
      index

      expect(response).to have_http_status(:bad_request)
      expect(json[:code]).to eq("total_count_first_page_only")
    end
  end

  context "when a required parameter is missing" do
    subject(:create_request) { post(:create, params: {}) }

    it "returns a bad request error keyed by the parameter, like the other v2 400s" do
      create_request

      expect(response).to have_http_status(:bad_request)
      expect(json).to eq(
        status: 400,
        error: "Bad Request",
        code: "missing_parameter",
        error_details: {product: {reason: "missing"}}
      )
    end
  end

  context "with offset pagination parameters on a list returned whole" do
    subject(:show) { get(:show, params: {id: "1", page: "2"}) }

    it "returns a bad request error" do
      show

      expect(response).to have_http_status(:bad_request)
      expect(json[:error_details]).to eq(page: {reason: "not_paginated"})
    end
  end
end
