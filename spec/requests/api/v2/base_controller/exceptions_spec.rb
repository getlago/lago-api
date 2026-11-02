# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v2 errors Rails answers itself" do # rubocop:disable RSpec/DescribeClass
  let(:organization) { create(:organization) }
  let(:headers) { {"Authorization" => "Bearer #{organization.api_keys.first.value}", "Content-Type" => "application/json"} }

  # As in production: the test environment shows detailed exceptions and raises the others. Rails
  # merges env_config over the request env, so it is stubbed rather than passed with the request.
  before do
    allow(Rails.application).to receive(:env_config).and_wrap_original do |original|
      original.call.merge("action_dispatch.show_exceptions" => :all, "action_dispatch.show_detailed_exceptions" => false)
    end
  end

  it "answers a malformed JSON body with the v2 400" do
    post "/api/v2/taxes", params: '{"tax": {', headers: headers

    expect(response).to have_http_status(:bad_request)
    expect(json).to eq(code: "bad_request", details: [])
    expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
  end

  it "answers a query string Rails cannot decode with the v2 400" do
    get "/api/v2/taxes?created_at_from=%FF", headers: headers

    expect(response).to have_http_status(:bad_request)
    expect(json).to eq(code: "bad_request", details: [])
  end

  context "when the action raises" do
    before { allow(TaxesQuery).to receive(:call).and_raise(StandardError, "boom") }

    it "answers the v2 500" do
      get "/api/v2/taxes", headers: headers

      expect(response).to have_http_status(:internal_server_error)
      expect(json).to eq(code: "internal_server_error", details: [])
    end
  end

  # The body fails to parse in the v1 controller's set_json_format, so Rails answers in the format of
  # the Accept header.
  it "leaves the shared /api/v2 routes to the Rails default of their v1 controllers" do
    post "/api/v2/coupons", params: '{"coupon": {', headers: headers.merge("Accept" => "application/json")

    expect(response).to have_http_status(:bad_request)
    expect(json).to eq(status: 400, error: "Bad Request")
  end
end
