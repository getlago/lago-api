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

  context "with the entitlements of a legacy plan" do
    let(:plan) { create(:plan, organization:) }
    let(:feature) { create(:feature, organization:, code: "seats", name: "Seats", description: nil) }
    let(:privilege) { create(:privilege, organization:, feature:, code: "max", name: nil, value_type: "integer") }
    let(:entitlement) { create(:entitlement, organization:, plan:, feature:) }
    let(:expected_body) do
      {
        entitlements: [
          {code: "seats", name: "Seats", description: nil, privileges: [{code: "max", name: nil, value_type: "integer", value: 30, config: {}}]}
        ]
      }
    end

    before { create(:entitlement_value, organization:, entitlement:, privilege:, value: "30") }

    it "lists them through the v1 controller, which only POST leaves" do
      get_with_token(organization, "/api/v2/plans/#{plan.code}/entitlements")

      expect(response).to have_http_status(:success)
      expect(json).to eq(expected_body)
    end

    it "updates them through the v1 controller" do
      patch_with_token(organization, "/api/v2/plans/#{plan.code}/entitlements", {entitlements: {seats: {max: 30}}})

      expect(response).to have_http_status(:success)
      expect(json).to eq(expected_body)
    end

    it "deletes one through the v1 controller" do
      delete_with_token(organization, "/api/v2/plans/#{plan.code}/entitlements/seats")

      expect(response).to have_http_status(:success)
      expect(json).to eq(entitlement: expected_body[:entitlements].sole)
    end

    it "no longer replaces them through the v1 controller, as POST is native" do
      post_with_token(organization, "/api/v2/plans/#{plan.code}/entitlements", {entitlements: {seats: {max: 40}}})

      expect(response).to be_v2_not_found_error("plan")
      expect(entitlement.values.sole.value).to eq("30")
    end
  end
end
