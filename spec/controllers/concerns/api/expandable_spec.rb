# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::Expandable, type: :controller do
  include ApiHelper

  controller(Api::V2::BaseController) do
    # A relation loaded in advance and a computed value, the two kinds a v2 serializer lists.
    expandable_with(
      Class.new(ModelSerializer) do
        def self.expandable_relations = {product_category: :product_category, computed: nil}.freeze
      end
    )

    # A lookup of the controller's own, like those of the v2 controllers.
    before_action(only: :show) { not_found_error(resource: "product") unless product }

    def index
      render(json: {includes: serializer_includes})
    end

    def show
      preload_expansions(product)
      loaded = Product.reflect_on_all_associations.map(&:name).select { product.association(it).loaded? }

      render(json: {includes: serializer_includes, loaded:})
    end

    def create
      render(json: {includes: serializer_includes})
    end

    private

    # Not through `current_organization.products`, which would mark `organization` as loaded.
    def product
      @product ||= Product.find_by(organization: current_organization, code: params[:id])
    end

    def resource_name
      "product"
    end
  end

  # A nil expand is left out of the request: a GET would send it as `expand=`, an empty value.
  subject(:show) { get(:show, params: {id: product.code, expand:}.compact) }

  let(:organization) { create(:organization, feature_flags:) }
  let(:feature_flags) { ["product_catalog"] }
  let(:product) { create(:product, organization:) }
  let(:allowed_values) { %w[product_category computed] }

  before { set_headers(organization, request.headers) }

  context "with a single expansion" do
    let(:expand) { ["product_category"] }

    it "passes it to the serializer and preloads its relation" do
      show

      expect(response).to have_http_status(:success)
      expect(json).to eq(includes: %w[product_category deleted_at], loaded: %w[product_category])
    end
  end

  [["product_category"], "product_category", {"0" => "product_category"}].each do |form|
    context "with expand sent as #{form.inspect}" do
      let(:expand) { form }

      it "reads the same expansion" do
        show

        expect(json).to eq(includes: %w[product_category deleted_at], loaded: %w[product_category])
      end
    end
  end

  context "with expansions in another order than the list" do
    let(:expand) { %w[computed product_category] }

    it "keeps the order of the list" do
      show

      expect(json[:includes]).to eq(%w[product_category computed deleted_at])
    end
  end

  context "with padded, repeated and blank values" do
    let(:expand) { [" computed ", "computed", "", "  "] }

    it "trims them and drops the blanks and duplicates" do
      show

      expect(response).to have_http_status(:success)
      expect(json[:includes]).to eq(%w[computed deleted_at])
    end
  end

  context "with a computed expansion" do
    let(:expand) { ["computed"] }

    it "preloads nothing" do
      show

      expect(json).to eq(includes: %w[computed deleted_at], loaded: [])
    end
  end

  context "without expand" do
    let(:expand) { nil }

    it "passes no expansion" do
      show

      expect(json).to eq(includes: %w[deleted_at], loaded: [])
    end
  end

  # nil stands for an absent expand.
  [nil, "", [""]].each do |empty|
    context "with an empty expand #{empty.inspect}" do
      let(:expand) { empty }

      it "passes no expansion on show" do
        show

        expect(response).to have_http_status(:success)
        expect(json[:includes]).to eq(%w[deleted_at])
      end

      it "passes no expansion on index" do
        get(:index, params: {expand: empty}.compact)

        expect(response).to have_http_status(:success)
        expect(json[:includes]).to eq(%w[deleted_at])
      end

      it "passes no expansion on create" do
        post(:create, params: {expand: empty}.compact, as: :json)

        expect(response).to have_http_status(:success)
        expect(json[:includes]).to eq(%w[deleted_at])
      end
    end
  end

  context "with an empty hash" do
    subject(:create_request) { post(:create, params: {expand: {}}, as: :json) }

    it "passes no expansion" do
      create_request

      expect(response).to have_http_status(:success)
      expect(json[:includes]).to eq(%w[deleted_at])
    end
  end

  context "with an unknown expansion" do
    let(:expand) { ["fees"] }

    it "returns a bad request error listing the allowed values" do
      show

      expect(response).to have_http_status(:bad_request)
      expect(json).to eq(
        status: 400,
        error: "Bad Request",
        code: "invalid_expand",
        error_details: {expand: {invalid_values: ["fees"], allowed_values: %w[product_category computed]}}
      )
    end
  end

  {
    "a dotted path" => ["product_category.billable_metric", ["product_category.billable_metric"]],
    "comma-separated names" => ["product_category,computed", ["product_category,computed"]],
    "a name in another case" => [["Product_Category"], ["Product_Category"]],
    "the counts option" => [["counts"], ["counts"]],
    "the deleted_at option" => [["deleted_at"], ["deleted_at"]],
    "valid and invalid names" => [["product_category", " fees ", "computed"], ["fees"]]
  }.each do |description, (value, invalid_values)|
    context "with #{description}" do
      let(:expand) { value }

      it "returns the invalid values" do
        show

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
        expect(json[:error_details]).to eq(expand: {invalid_values:, allowed_values:})
      end
    end
  end

  {
    "a hash keyed by a name" => {"a" => "product_category"},
    "a hash keyed by a negative index" => {"-1" => "product_category"},
    "a hash keyed by a decimal index" => {"1.5" => "product_category"},
    "a hash mixing numeric and other keys" => {"0" => "product_category", "a" => "computed"},
    "a nested hash" => {"0" => {"x" => "product_category"}},
    "a hash nesting an array" => {"0" => ["product_category"]},
    "a nested array" => [["product_category"]],
    "an array nesting a hash" => [{"x" => "product_category"}]
  }.each do |description, value|
    context "with #{description}" do
      let(:expand) { value }

      it "returns a malformed error" do
        show

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
        expect(json[:error_details]).to eq(expand: {reason: "malformed", allowed_values:})
      end
    end
  end

  [1, false, [1]].each do |value|
    context "with the JSON value #{value.inspect}" do
      subject(:create_request) { post(:create, params: {expand: value}, as: :json) }

      it "returns a malformed error" do
        create_request

        expect(response).to have_http_status(:bad_request)
        expect(json[:error_details]).to eq(expand: {reason: "malformed", allowed_values: []})
      end
    end
  end

  context "with an expansion on index" do
    subject(:index) { get(:index, params: {expand: ["product_category"]}) }

    it "rejects it, as nothing is expandable there" do
      index

      expect(response).to have_http_status(:bad_request)
      expect(json[:error_details]).to eq(expand: {invalid_values: ["product_category"], allowed_values: []})
    end
  end

  context "with an expansion on create" do
    subject(:create_request) { post(:create, params: {expand: ["product_category"]}, as: :json) }

    it "rejects it, as nothing is expandable there" do
      create_request

      expect(response).to have_http_status(:bad_request)
      expect(json[:error_details]).to eq(expand: {invalid_values: ["product_category"], allowed_values: []})
    end
  end

  context "with an unknown product" do
    subject(:show) { get(:show, params: {id: "unknown", expand:}) }

    context "with a valid expansion" do
      let(:expand) { ["product_category"] }

      it "returns a not found error" do
        show

        expect(response).to be_not_found_error("product")
      end
    end

    context "with an invalid expansion" do
      let(:expand) { ["fees"] }

      it "rejects the expansion before the lookup" do
        show

        expect(response).to have_http_status(:bad_request)
        expect(json[:code]).to eq("invalid_expand")
      end
    end
  end

  context "when the organization is not on the product catalog" do
    let(:feature_flags) { [] }
    let(:expand) { ["fees"] }

    it "checks the catalog before the expansion" do
      show

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("feature_unavailable")
    end
  end

  context "without a valid API key" do
    let(:expand) { ["fees"] }

    before { request.headers["Authorization"] = "Bearer invalid" }

    it "authenticates before checking the expansion" do
      show

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
