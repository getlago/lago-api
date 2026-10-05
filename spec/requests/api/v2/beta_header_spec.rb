# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v2 beta header" do
  let(:organization) { create(:organization) }
  let(:header) { response.headers["X-Lago-Endpoint-Status"] }

  it "is set on a successful response" do
    get_with_token(organization, "/api/v2/plans")

    expect(response).to have_http_status(:success)
    expect(header).to eq("beta")
  end

  it "is set on an unauthorized response" do
    get("/api/v2/plans", headers: {"Authorization" => "Bearer invalid"})

    expect(response).to have_http_status(:unauthorized)
    expect(header).to eq("beta")
  end

  context "when the organization is not on the product catalog", product_catalog: false do
    it "is set on a forbidden response" do
      get_with_token(organization, "/api/v2/plans")

      expect(response).to have_http_status(:forbidden)
      expect(header).to eq("beta")
    end
  end

  it "is set on the paths still served by v1 controllers" do
    get_with_token(organization, "/api/v2/billable_metrics")

    expect(response).to have_http_status(:success)
    expect(header).to eq("beta")
  end

  it "is not set on v1" do
    get_with_token(organization, "/api/v1/billable_metrics")

    expect(response).to have_http_status(:success)
    expect(response.headers).not_to have_key("X-Lago-Endpoint-Status")
  end
end
