# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionEntitlementPrivilegeDestroyService, type: :service do
  subject(:result) { described_class.call(subscription:, feature_code:, privilege_code:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:privilege) { create(:privilege, feature:, code: "max", value_type: "integer") }
  let(:entitlement) { create(:entitlement, subscription_id: subscription.id, plan: nil, feature:) }
  let(:entitlement_value) { create(:entitlement_value, entitlement:, privilege:, value: "30", organization:) }
  let(:feature_code) { feature.code }
  let(:privilege_code) { privilege.code }

  before do
    entitlement
    entitlement_value
  end

  it_behaves_like "a premium service"

  describe "#call" do
    around { |test| lago_premium!(&test) }

    it "returns success" do
      expect(result).to be_success
    end

    it "deletes the entitlement value" do
      expect { result }.to change(feature.entitlement_values, :count).by(-1)
    end

    it "does not delete the entitlement" do
      expect { result }.not_to change(feature.entitlements, :count)
    end

    it "sends `subscription.updated` webhook" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("subscription.updated", subscription)
    end

    it "produces an activity log" do
      subject
      expect(Utils::ActivityLog).to have_produced("subscription.updated").after_commit.with(subscription)
    end

    context "when entitlement does not exist" do
      let(:feature_code) { "nonexistent_feature" }

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("entitlement_not_found")
      end
    end

    context "when privilege does not exist" do
      let(:privilege_code) { "nonexistent_privilege" }

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("privilege_not_found")
      end
    end
  end
end
