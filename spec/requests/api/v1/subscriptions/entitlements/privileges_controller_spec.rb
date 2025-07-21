# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Subscriptions::Entitlements::PrivilegesController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:privilege) { create(:privilege, organization:, feature:, code: "max", value_type: "integer") }
  let(:entitlement) { create(:entitlement, subscription_id: subscription.id, plan: nil, feature:) }
  let(:entitlement_value) { create(:entitlement_value, entitlement:, privilege:, value: 30, organization:) }

  around { |test| lago_premium!(&test) }

  describe "DELETE #destroy" do
    subject { delete_with_token organization, "/api/v1/subscriptions/#{subscription.external_id}/entitlements/#{feature.code}/privileges/#{privilege.code}" }

    before do
      entitlement
      entitlement_value
    end

    it_behaves_like "a Premium API endpoint"

    it "deletes the entitlement value" do
      expect { subject }.to change(feature.entitlement_values, :count).by(-1)

      expect(response).to have_http_status(:success)
    end

    it "does not delete the entitlement" do
      expect { subject }.not_to change(feature.entitlements, :count)
    end

    it "returns not found error when subscription does not exist" do
      delete_with_token organization, "/api/v1/subscriptions/invalid_subscription/entitlements/#{feature.code}/privileges/#{privilege.code}"

      expect(response).to be_not_found_error("subscription")
    end

    it "returns not found error when entitlement does not exist" do
      delete_with_token organization, "/api/v1/subscriptions/#{subscription.external_id}/entitlements/invalid_feature/privileges/#{privilege.code}"

      expect(response).to be_not_found_error("entitlement")
    end

    it "returns not found error when privilege does not exist" do
      delete_with_token organization, "/api/v1/subscriptions/#{subscription.external_id}/entitlements/#{feature.code}/privileges/invalid_privilege"

      expect(response).to be_not_found_error("privilege")
    end
  end
end
