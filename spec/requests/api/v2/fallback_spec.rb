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

  # The privilege delete was the last features action served by v1.
  it "serves the features privilege delete natively, without falling back to v1" do
    delete_with_token(organization, "/api/v2/features/unknown/privileges/max")

    expect(response).to be_v2_not_found_error("feature")
  end

  context "with the entitlements of a legacy plan" do
    let(:plan) { create(:plan, organization:) }
    let(:feature) { create(:feature, organization:, code: "seats", name: "Seats", description: nil) }
    let(:privilege) { create(:privilege, organization:, feature:, code: "max", name: nil, value_type: "integer") }
    let(:entitlement) { create(:entitlement, organization:, plan:, feature:) }

    before { create(:entitlement_value, organization:, entitlement:, privilege:, value: "30") }

    it "no longer lists them through the v1 controller, as GET is native" do
      get_with_token(organization, "/api/v2/plans/#{plan.code}/entitlements")

      expect(response).to be_v2_not_found_error("plan")
    end

    it "no longer shows one through the v1 controller, as GET is native" do
      get_with_token(organization, "/api/v2/plans/#{plan.code}/entitlements/seats")

      expect(response).to be_v2_not_found_error("plan")
      expect(entitlement.values.sole.value).to eq("30")
    end

    it "no longer updates them through the v1 controller, as PATCH is native" do
      patch_with_token(organization, "/api/v2/plans/#{plan.code}/entitlements", {entitlements: {seats: {max: 40}}})

      expect(response).to be_v2_not_found_error("plan")
      expect(entitlement.values.sole.value).to eq("30")
    end

    it "no longer deletes one through the v1 controller, as DELETE is native" do
      delete_with_token(organization, "/api/v2/plans/#{plan.code}/entitlements/seats")

      expect(response).to be_v2_not_found_error("plan")
      expect(entitlement.reload).not_to be_discarded
      expect(entitlement.values.sole.value).to eq("30")
    end

    it "no longer deletes a privilege value through the v1 controller, as DELETE is native" do
      delete_with_token(organization, "/api/v2/plans/#{plan.code}/entitlements/seats/privileges/max")

      expect(response).to be_v2_not_found_error("plan")
      expect(entitlement.reload).not_to be_discarded
      expect(entitlement.values.sole.value).to eq("30")
    end

    it "does not destroy a plan through the v1 controller on a DELETE of the collection" do
      # The greedy v1 :code would read this path as the code of this plan.
      greedy_match = create(:plan, organization:, code: "#{plan.code}/entitlements")

      delete_with_token(organization, "/api/v2/plans/#{plan.code}/entitlements")

      expect(response).to be_not_found_error("resource")
      expect(greedy_match.reload).not_to be_discarded
      expect(plan.reload).not_to be_discarded
      expect(entitlement.reload).not_to be_discarded
    end

    it "no longer replaces them through the v1 controller, as POST is native" do
      post_with_token(organization, "/api/v2/plans/#{plan.code}/entitlements", {entitlements: {seats: {max: 40}}})

      expect(response).to be_v2_not_found_error("plan")
      expect(entitlement.values.sole.value).to eq("30")
    end
  end
end
