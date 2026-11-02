# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::UnknownV2RoutesController do
  let_it_be(:organization) { create(:organization) }

  [
    [:get, "/api/v2"],
    [:get, "/api/v2/unknown"],
    [:delete, "/api/v2/payments/abc"],
    [:post, "/api/v2/credit_notes/abc/download"],
    [:options, "/api/v2/plans"]
  ].each do |verb, path|
    it "answers the v2 404 to #{verb.upcase} #{path}, whatever the key" do
      process(verb, path, headers: {"Authorization" => "Bearer #{organization.api_keys.first.value}"})

      expect(response).to have_http_status(:not_found)
      expect(json).to eq(code: "resource_not_found", details: [])
      expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")

      process(verb, path)

      expect(response).to have_http_status(:not_found)
      expect(json).to eq(code: "resource_not_found", details: [])
    end
  end

  it "leaves the shared /api/v2 routes to their v1 controllers" do
    get_with_token(organization, "/api/v2/coupons")

    expect(response).to have_http_status(:success)
  end

  it "leaves the paths outside /api/v2 to the v1 404" do
    get_with_token(organization, "/api/v1/unknown")

    expect(response).to be_not_found_error("resource")
    expect(response.headers).not_to have_key("X-Lago-Endpoint-Status")
  end
end
