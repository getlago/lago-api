# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Plans::Entitlements::PrivilegesController, type: :request do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege) { create(:privilege, organization:, feature:, code: "max_users") }
  let(:privilege2) { create(:privilege, organization:, feature:, code: "max_admins") }
  let(:entitlement) { create(:entitlement, organization:, plan:, feature:) }
  let(:entitlement_value) { create(:entitlement_value, entitlement:, privilege:, organization:) }
  let(:entitlement_value2) { create(:entitlement_value, entitlement:, privilege: privilege2, organization:) }

  before do
    entitlement_value
    entitlement_value2
  end

  describe "DELETE #destroy" do
    it "deletes the specific privilege value from the entitlement" do
      expect {
        delete_with_token organization, "/api/v1/plans/#{plan.code}/entitlements/#{feature.code}/privileges/#{privilege.code}"
      }.to change { Entitlement::EntitlementValue.kept.count }.by(-1)

      expect(response).to have_http_status(:success)

      expect(json[:entitlement][:privileges]).to have_key(privilege2.code.to_sym)
      expect(json[:entitlement][:privileges]).not_to have_key(privilege.code.to_sym)
    end

    it "returns not found error when plan does not exist" do
      delete_with_token organization, "/api/v1/plans/invalid_plan/entitlements/#{feature.code}/privileges/#{privilege.code}"

      expect(response).to be_not_found_error("plan")
    end

    it "returns not found error when entitlement does not exist" do
      delete_with_token organization, "/api/v1/plans/#{plan.code}/entitlements/invalid_feature/privileges/#{privilege.code}"

      expect(response).to be_not_found_error("entitlement")
    end

    it "returns not found error when privilege does not exist" do
      delete_with_token organization, "/api/v1/plans/#{plan.code}/entitlements/#{feature.code}/privileges/invalid_privilege"

      expect(response).to be_not_found_error("privilege")
    end

    it "returns the updated entitlement in the response" do
      delete_with_token organization, "/api/v1/plans/#{plan.code}/entitlements/#{feature.code}/privileges/#{privilege.code}"

      expect(response).to have_http_status(:success)

      json = JSON.parse(response.body, symbolize_names: true)
      expect(json[:entitlement][:code]).to eq(feature.code)
      expect(json[:entitlement][:privileges]).to have_key(privilege2.code.to_sym)
      expect(json[:entitlement][:privileges][privilege2.code.to_sym][:value]).to eq(entitlement_value2.value)
    end
  end
end
