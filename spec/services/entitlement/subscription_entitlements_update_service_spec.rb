# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionEntitlementsUpdateService, type: :service do
  subject(:result) { described_class.call(organization:, subscription:, entitlements_params:, partial: false) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:privilege) { create(:privilege, organization:, feature:, code: "max", value_type: "integer") }
  let(:entitlements_params) do
    {
      "seats" => {
        "max" => 25
      }
    }
  end

  before do
    feature
    privilege
  end

  it_behaves_like "a premium service"

  describe "#call" do
    around { |test| lago_premium!(&test) }

    it "returns success" do
      expect(result).to be_success
    end

    it "creates entitlements for the subscription" do
      expect { result }.to change { subscription.entitlements.count }.by(1)
    end

    it "creates entitlement values" do
      expect { result }.to change(Entitlement::EntitlementValue, :count).by(1)
    end

    it "sends `subscription.updated` webhook" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("subscription.updated", subscription)
    end

    it "produces an activity log" do
      subject
      expect(Utils::ActivityLog).to have_produced("subscription.updated").after_commit.with(subscription)
    end

    it "creates the entitlement with correct values" do
      result
      entitlement = subscription.entitlements.first
      entitlement_value = entitlement.values.first

      expect(entitlement.feature).to eq(feature)
      expect(entitlement_value.privilege).to eq(privilege)
      expect(entitlement_value.value).to eq("25")
    end

    context "when subscription does not exist" do
      let(:subscription) { nil }

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("subscription_not_found")
      end
    end

    context "when feature does not exist" do
      let(:entitlements_params) do
        {
          "nonexistent_feature" => {
            "max" => 25
          }
        }
      end

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("feature_not_found")
      end
    end

    context "when privilege does not exist" do
      let(:entitlements_params) do
        {
          "seats" => {
            "nonexistent_privilege" => 25
          }
        }
      end

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("privilege_not_found")
      end
    end

    context "when subscription has existing entitlements" do
      let(:existing_entitlement) { create(:entitlement, organization:, subscription_external_id: subscription.external_id, plan: nil, feature:) }
      let(:existing_value) { create(:entitlement_value, entitlement: existing_entitlement, privilege:, value: "10", organization:) }

      before do
        existing_entitlement
        existing_value
      end

      it "replaces existing entitlements" do
        result

        expect(result).to be_success
        expect(subscription.entitlements.first.values.first.value).to eq("25")
      end
    end

    context "when partial is true" do
      subject(:result) { described_class.call(organization:, subscription:, entitlements_params:, partial: true) }

      let(:existing_entitlement) { create(:entitlement, organization:, subscription_external_id: subscription.external_id, plan: nil, feature:) }
      let(:existing_value) { create(:entitlement_value, entitlement: existing_entitlement, privilege:, value: "10", organization:) }
      let(:other_feature) { create(:feature, organization:, code: "storage") }
      let(:other_privilege) { create(:privilege, organization:, feature: other_feature, code: "limit", value_type: "integer") }
      let(:other_entitlement) { create(:entitlement, organization:, subscription_external_id: subscription.external_id, plan: nil, feature: other_feature) }
      let(:other_value) { create(:entitlement_value, entitlement: other_entitlement, privilege: other_privilege, value: "100", organization:) }

      before do
        existing_entitlement
        existing_value
        other_entitlement
        other_value
      end

      it "keeps existing entitlements not in params" do
        result

        expect(result).to be_success
        expect(subscription.entitlements.count).to eq(2)
        expect(subscription.entitlements.find_by(feature: other_feature)).to be_present
      end
    end
  end
end
