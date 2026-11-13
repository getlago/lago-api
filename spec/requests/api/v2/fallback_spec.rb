# frozen_string_literal: true

require "rails_helper"

# v1 controllers serve these routes, so with v1 timestamps.
RSpec.describe "API v2 fallback to v1", v2_timestamps: false do
  let(:organization) { create(:organization) }
  let(:add_on) { create(:add_on, organization:) }

  it "serves a v1-backed resource under /api/v2" do
    add_on

    get_with_token(organization, "/api/v2/add_ons")

    expect(response).to have_http_status(:success)
    expect(json[:add_ons].map { it[:lago_id] }).to eq([add_on.id])
  end

  it "ignores expands, which only the native v2 controllers validate" do
    get_with_token(organization, "/api/v2/add_ons?expands[]=__nope__")

    expect(response).to have_http_status(:success)
  end

  it "renders the v1 error body, which only the native v2 controllers replace" do
    get_with_token(organization, "/api/v2/add_ons/unknown")

    expect(response).to be_not_found_error("add_on")
    expect(json).not_to have_key(:details)
  end

  # The features index and show are native: create, update and destroy stay on v1 until they are.
  context "with the features actions v2 does not serve natively" do
    let(:feature) { create(:feature, organization:, code: "seats", name: "Seats", description: "Number of seats") }

    before { create(:privilege, feature:, code: "max", name: "Maximum", value_type: "integer") }

    it "serves the index and the show natively" do
      get_with_token(organization, "/api/v2/features")

      expect(response).to have_http_status(:success)
      expect(json[:features].map { it[:lago_id] }).to eq([feature.id])
      expect(json[:features].first).not_to have_key(:privileges)
      expect(json[:meta]).not_to have_key(:current_page)

      get_with_token(organization, "/api/v2/features/seats")

      expect(response).to have_http_status(:success)
      expect(json[:feature][:lago_id]).to eq(feature.id)
      expect(json[:feature]).not_to have_key(:privileges)
    end

    it "creates a feature with the v1 body" do
      post_with_token(organization, "/api/v2/features", {feature: {code: "storage", name: "Storage", privileges: [{code: "gb", value_type: "integer"}]}})

      expect(response).to have_http_status(:success)
      expect(json[:feature]).not_to have_key(:lago_id)
      expect(json[:feature]).to include(code: "storage", privileges: [{code: "gb", name: nil, value_type: "integer", config: {}}])
    end

    it "updates a feature with the v1 body" do
      put_with_token(organization, "/api/v2/features/seats", {feature: {name: "Renamed"}})

      expect(response).to have_http_status(:success)
      expect(json[:feature]).not_to have_key(:lago_id)
      expect(json[:feature]).to include(code: "seats", name: "Renamed")
    end

    it "deletes a feature with the v1 body" do
      delete_with_token(organization, "/api/v2/features/seats")

      expect(response).to have_http_status(:success)
      expect(json[:feature]).not_to have_key(:lago_id)
      expect(json[:feature]).to include(code: "seats")
      expect(feature.reload.deleted_at).to be_present
    end

    it "ignores an expansion on an update and answers with the v1 body" do
      put_with_token(organization, "/api/v2/features/seats?expands[]=privileges", {feature: {name: "Renamed"}})

      expect(response).to have_http_status(:success)
      expect(json[:feature]).not_to have_key(:lago_id)
      expect(json[:feature]).to include(code: "seats", name: "Renamed", privileges: [{code: "max", name: "Maximum", value_type: "integer", config: {}}])
    end

    it "renders the v1 not found error for an unknown feature" do
      put_with_token(organization, "/api/v2/features/unknown", {feature: {name: "X"}})

      expect(response).to be_not_found_error("feature")
      expect(json).not_to have_key(:details)
    end
  end
end
