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

  # Every features action is native: only the privilege delete stays on v1.
  context "with the features actions v2 does not serve natively" do
    let(:feature) { create(:feature, organization:, code: "seats", name: "Seats", description: "Number of seats") }

    let(:privilege) { create(:privilege, feature:, code: "max", name: "Maximum", value_type: "integer") }

    before { privilege }

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

    it "deletes a privilege of a feature with the v1 body" do
      delete_with_token(organization, "/api/v2/features/seats/privileges/max")

      expect(response).to have_http_status(:success)
      expect(json[:feature]).not_to have_key(:lago_id)
      expect(json[:feature]).to include(code: "seats", privileges: [])
      expect(privilege.reload.deleted_at).to be_present
      expect(feature.reload.deleted_at).to be_nil
    end

    it "ignores an expansion on a privilege delete and answers with the v1 body" do
      delete_with_token(organization, "/api/v2/features/seats/privileges/max?expands[]=privileges")

      expect(response).to have_http_status(:success)
      expect(json[:feature]).not_to have_key(:lago_id)
      expect(json[:feature]).to include(code: "seats", privileges: [])
    end

    it "renders the v1 not found error for an unknown feature" do
      delete_with_token(organization, "/api/v2/features/unknown/privileges/max")

      expect(response).to be_not_found_error("feature")
      expect(json).not_to have_key(:details)
    end
  end
end
