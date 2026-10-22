# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::Serializable do
  # A nil value is left out of the request.
  subject(:show) { get_with_token(organization, "/api/v2/serializable_tests/#{product.code}", {expands:}.compact) }

  # Out of spec/requests/api/v2, the catalog flag is not set for the spec.
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:product_category) { create(:product_category, organization:) }
  let(:product) { create(:product, organization:, product_category:) }
  let(:expands) { nil }
  let(:product_category_payload) { ::V2::ProductCategorySerializer.new(product_category).serialize }

  # Two expansions, so that their order and a repeated key can be told apart.
  let(:serializer) do
    metric_serializer = Class.new(ModelSerializer) { def serialize = {code: model.code} }

    Class.new(ModelSerializer) do
      expandable :product_category, serializer: ::V2::ProductCategorySerializer
      expandable :billable_metric, serializer: metric_serializer

      def serialize = {code: model.code}
    end
  end

  # v2 controllers of the test's own, drawn on routes of their own for each example.
  around do |example|
    with_routing do |routes|
      routes.draw do
        namespace :api do
          namespace :v2 do
            resources :serializable_tests, only: %i[index show create update]
            resources :whole_list_tests, only: %i[index show]
            resources :not_serializable_tests, only: %i[show]
            resources :not_expanding_tests, only: %i[show]
          end
        end
      end

      example.run
    end
  end

  before do
    serializer = self.serializer

    stub_const("Api::V2::SerializableTestsController", Class.new(Api::V2::BaseController) do
      cursor_paginated_index(Product)
      # An anonymous class has no controller name to take the root from.
      serializable_with(serializer, root: :product, expand_on: %i[show update])

      # A lookup of the controller's own, like those of the v2 controllers.
      before_action(only: %i[show update]) { not_found_error(resource: "product") unless product }

      def index
        render_products(::CursorPagination::Keyset.apply(Product.where(organization: current_organization), cursor))
      end

      def show
        render_product(product)
      end

      def create
        render(json: {created: true})
      end

      def update
        render_product(product)
      end

      private

      def product
        @product ||= current_organization.products.find_by(code: params[:id])
      end

      def resource_name
        "product"
      end
    end)

    stub_const("Api::V2::WholeListTestsController", Class.new(Api::V2::BaseController) do
      serializable_with(Class.new(ModelSerializer) { def serialize = {code: model.code} }, root: :product)

      def index
        render_products(current_organization.products.order(:code))
      end

      def show
        render_product(current_organization.products.find_by(code: params[:id]))
      end

      private

      def resource_name
        "product"
      end
    end)

    # Its serializer declares expansions, but none of its actions expands.
    stub_const("Api::V2::NotExpandingTestsController", Class.new(Api::V2::BaseController) do
      serializable_with(serializer, root: :product, expand_on: [])

      def show
        render_product(current_organization.products.find_by(code: params[:id]))
      end

      private

      def resource_name
        "product"
      end
    end)

    stub_const("Api::V2::NotSerializableTestsController", Class.new(Api::V2::BaseController) do
      def show
        render(json: {ok: true})
      end

      private

      def resource_name
        "product"
      end
    end)
  end

  it "renders the record under its root, without expansions" do
    show

    expect(response).to have_http_status(:success)
    expect(json).to eq(product: {code: product.code})
  end

  context "with an expansion" do
    let(:expands) { ["product_category"] }

    it "embeds the record as its serializer renders it" do
      show

      expect(response).to have_http_status(:success)
      expect(json).to eq(product: {code: product.code, product_category: product_category_payload})
    end

    context "when the record has none" do
      let(:product) { create(:product, :fixed, :standalone, organization:) }

      it "renders it as null" do
        show

        expect(json).to eq(product: {code: product.code, product_category: nil})
      end
    end
  end

  context "with expansions in another order than the serializer's" do
    let(:expands) { %w[billable_metric product_category] }

    it "renders them in the serializer's order" do
      show

      expect(json[:product].keys).to eq(%i[code product_category billable_metric])
      expect(json[:product][:billable_metric]).to eq(code: product.billable_metric.code)
    end
  end

  # Rails reads a bare key sent twice as its last value, a string.
  context "with expands sent as a bare key repeated" do
    subject(:show) { get_with_token(organization, "/api/v2/serializable_tests/#{product.code}?expands=product_category&expands=billable_metric") }

    it "returns a malformed error" do
      show

      expect(response).to have_http_status(:bad_request)
      expect(json[:error_details]).to eq(expands: {reason: "malformed", allowed_values: %w[product_category billable_metric]})
    end
  end

  context "with the singular expand parameter" do
    subject(:show) { get_with_token(organization, "/api/v2/serializable_tests/#{product.code}", {expand: ["product_category"]}) }

    it "ignores it, as any parameter the endpoint does not read" do
      show

      expect(response).to have_http_status(:success)
      expect(json).to eq(product: {code: product.code})
    end
  end

  context "with padded, repeated and blank values" do
    let(:expands) { [" billable_metric ", "billable_metric", "", "  "] }

    it "trims them and drops the blanks and duplicates" do
      show

      expect(response).to have_http_status(:success)
      expect(json[:product].keys).to eq(%i[code billable_metric])
    end
  end

  [nil, [], [""]].each do |empty|
    context "with an empty expands #{empty.inspect}" do
      let(:expands) { empty }

      it "renders no expansion on show" do
        show

        expect(response).to have_http_status(:success)
        expect(json).to eq(product: {code: product.code})
      end

      it "accepts it on an action that does not expand" do
        post_with_token(organization, "/api/v2/serializable_tests", {expands: empty}.compact)

        expect(response).to have_http_status(:success)
        expect(json).to eq(created: true)
      end
    end
  end

  context "with an unknown expansion" do
    let(:expands) { ["fees"] }

    it "returns a bad request error listing the allowed values" do
      show

      expect(response).to have_http_status(:bad_request)
      expect(json).to eq(
        status: 400,
        error: "Bad Request",
        code: "invalid_expand",
        error_details: {expands: {invalid_values: ["fees"], allowed_values: %w[product_category billable_metric]}}
      )
    end
  end

  {
    "a dotted path" => [["product_category.billable_metric"], ["product_category.billable_metric"]],
    "comma-separated names" => [["product_category,billable_metric"], ["product_category,billable_metric"]],
    "a name in another case" => [["Product_Category"], ["Product_Category"]],
    "valid and invalid names" => [["product_category", " fees ", "billable_metric"], ["fees"]]
  }.each do |description, (value, invalid_values)|
    context "with #{description}" do
      let(:expands) { value }

      it "returns the invalid values" do
        show

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
        expect(json[:error_details]).to eq(expands: {invalid_values:, allowed_values: %w[product_category billable_metric]})
      end
    end
  end

  context "with an unknown expansion repeated" do
    let(:expands) { ["fees", " fees "] }

    it "returns it once" do
      show

      expect(json[:error_details]).to eq(expands: {invalid_values: ["fees"], allowed_values: %w[product_category billable_metric]})
    end
  end

  {
    "a bare value" => "product_category",
    "an empty bare value" => "",
    "an indexed hash" => {"0" => "product_category"},
    "a hash keyed by a name" => {"a" => "product_category"},
    "an array nesting a hash" => [{"x" => "product_category"}]
  }.each do |description, value|
    context "with #{description}" do
      let(:expands) { value }

      it "returns a malformed error" do
        show

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
        expect(json[:error_details]).to eq(expands: {reason: "malformed", allowed_values: %w[product_category billable_metric]})
      end
    end
  end

  # Sent as a query string, which the test client would flatten into `expands[]=product_category`.
  context "with a nested array" do
    subject(:show) { get_with_token(organization, "/api/v2/serializable_tests/#{product.code}?expands[][]=product_category") }

    it "returns a malformed error" do
      show

      expect(response).to have_http_status(:bad_request)
      expect(json[:error_details]).to eq(expands: {reason: "malformed", allowed_values: %w[product_category billable_metric]})
    end
  end

  [1, false, "product_category", {}, [1]].each do |value|
    context "with the JSON value #{value.inspect} on an action that does not expand" do
      subject(:create_request) { post_with_token(organization, "/api/v2/serializable_tests", {expands: value}) }

      it "returns a malformed error, with nothing allowed" do
        create_request

        expect(response).to have_http_status(:bad_request)
        expect(json[:error_details]).to eq(expands: {reason: "malformed", allowed_values: []})
      end
    end
  end

  context "with an expansion on index" do
    subject(:index) { get_with_token(organization, "/api/v2/serializable_tests", {expands: ["product_category"]}) }

    it "returns a not supported error, as lists never expand" do
      index

      expect(response).to have_http_status(:bad_request)
      expect(json).to eq(
        status: 400,
        error: "Bad Request",
        code: "expand_not_supported",
        error_details: {expands: {reason: "action_not_expandable", invalid_values: ["product_category"]}}
      )
    end
  end

  context "with an expansion on an action left out of expand_on" do
    subject(:create_request) { post_with_token(organization, "/api/v2/serializable_tests", {expands: ["product_category"]}) }

    it "returns a not supported error before the action runs" do
      create_request

      expect(response).to have_http_status(:bad_request)
      expect(json[:code]).to eq("expand_not_supported")
      expect(json[:error_details]).to eq(expands: {reason: "action_not_expandable", invalid_values: ["product_category"]})
    end
  end

  context "with an expansion on another action of expand_on" do
    subject(:update_request) { put_with_token(organization, "/api/v2/serializable_tests/#{product.code}?expands[]=product_category", {}) }

    it "embeds the record" do
      update_request

      expect(response).to have_http_status(:success)
      expect(json).to eq(product: {code: product.code, product_category: product_category_payload})
    end
  end

  context "with a serializer that declares no expansion" do
    subject(:show) { get_with_token(organization, "/api/v2/whole_list_tests/#{product.code}", {expands: ["product_category"]}) }

    it "returns a not supported error, as nothing expands there" do
      show

      expect(response).to have_http_status(:bad_request)
      expect(json[:code]).to eq("expand_not_supported")
      expect(json[:error_details]).to eq(expands: {reason: "not_expandable", invalid_values: ["product_category"]})
    end
  end

  context "with a serializer that declares expansions and an empty expand_on" do
    subject(:show) { get_with_token(organization, "/api/v2/not_expanding_tests/#{product.code}", {expands: ["product_category"]}) }

    it "returns a not supported error, as nothing expands there" do
      show

      expect(response).to have_http_status(:bad_request)
      expect(json[:error_details]).to eq(expands: {reason: "not_expandable", invalid_values: ["product_category"]})
    end
  end

  context "without serializable_with" do
    subject(:show) { get_with_token(organization, "/api/v2/not_serializable_tests/#{product.code}", {expands:}.compact) }

    it "renders on its own" do
      show

      expect(json).to eq(ok: true)
    end

    context "with an expansion" do
      let(:expands) { ["product_category"] }

      it "returns a not supported error, as nothing expands there" do
        show

        expect(response).to have_http_status(:bad_request)
        expect(json[:error_details]).to eq(expands: {reason: "not_expandable", invalid_values: ["product_category"]})
      end
    end
  end

  context "with a cursor-paginated index" do
    subject(:index) { get_with_token(organization, "/api/v2/serializable_tests", {limit: 1}) }

    let(:older_product) { create(:product, organization:, created_at: 1.day.ago) }

    before { [product, older_product] }

    it "renders one page under the collection name, with its cursors" do
      index

      expect(response).to have_http_status(:success)
      expect(json[:products]).to eq([{code: product.code}])
      expect(json[:meta]).to eq(next_cursor: CursorPagination::Token.encode(table: "products", record: product), prev_cursor: nil)
    end
  end

  context "with a list returned whole" do
    subject(:index) { get_with_token(organization, "/api/v2/whole_list_tests") }

    let(:product) { create(:product, organization:, code: "b_product") }
    let(:other_product) { create(:product, organization:, code: "a_product") }

    before { [product, other_product] }

    it "renders every record under the collection name, without meta" do
      index

      expect(response).to have_http_status(:success)
      expect(json).to eq(products: [{code: other_product.code}, {code: product.code}])
    end
  end

  context "with an unknown product" do
    subject(:show) { get_with_token(organization, "/api/v2/serializable_tests/unknown", {expands:}) }

    context "with a valid expansion" do
      let(:expands) { ["product_category"] }

      it "returns a not found error" do
        show

        expect(response).to be_not_found_error("product")
      end
    end

    context "with an invalid expansion" do
      let(:expands) { ["fees"] }

      it "rejects the expansion before the lookup" do
        show

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
      end
    end
  end

  context "when the organization is not on the product catalog" do
    let(:organization) { create(:organization) }
    let(:expands) { ["fees"] }

    it "checks the catalog before the expansion" do
      show

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("feature_unavailable")
    end
  end

  context "without a valid API key" do
    subject(:show) { get("/api/v2/serializable_tests/#{product.code}", params: {expands: ["fees"]}, headers: {"Authorization" => "Bearer invalid"}) }

    it "authenticates before checking the expansion" do
      show

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "when declared" do
    it "keeps the generated render methods out of the actions" do
      expect(Api::V2::SerializableTestsController.action_methods).to include("show")
      expect(Api::V2::SerializableTestsController.action_methods).not_to include("render_product", "render_products")
    end

    it "refuses to expand an index" do
      expect { Class.new(Api::V2::BaseController) { serializable_with(ModelSerializer, root: :product, expand_on: %i[show index]) } }
        .to raise_error(ArgumentError, /cannot expand its index/)
    end

    it "needs a root on a class without a name" do
      expect { Class.new(Api::V2::BaseController) { serializable_with(ModelSerializer) } }
        .to raise_error(ArgumentError, /needs a root/)
    end
  end
end
