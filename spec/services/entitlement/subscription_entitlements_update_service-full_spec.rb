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

  let(:feature2) { create(:feature, code: "storage", organization:) }
  let(:privilege2) { create(:privilege, feature: feature2, code: "limit", value_type: "integer") }
  let(:privilege3) { create(:privilege, feature: feature2, code: "allow_overage", value_type: "boolean") }

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

    context "when plan already has the feature" do
      let(:existing_entitlement) { create(:entitlement, organization:, plan:, feature:) }
      let(:existing_value) { create(:entitlement_value, entitlement: existing_entitlement, privilege:, value: "10", organization:) }

      it "creates an override" do
        result

        expect(result).to be_success
        expect(existing_value.value).to eq "10"
        expect(subscription.entitlements.except(existing_entitlement).sole.values.sole.value).to eq("25")
      end
    end

    context "when subscription has existing entitlements" do
      let(:existing_entitlement) { create(:entitlement, organization:, subscription_id: subscription.id, plan: nil, feature:) }
      let(:existing_value) { create(:entitlement_value, entitlement: existing_entitlement, privilege:, value: "10", organization:) }

      before do
        existing_entitlement
        existing_value
      end

      it "replaces existing entitlements" do
        result

        expect(result).to be_success
        expect(existing_value.reload.value).to eq("25")
      end
    end

    context "when plan has a feature but it's not part of the params anymore" do
      let(:existing_entitlement) { create(:entitlement, organization:, plan:, feature:) }
      let(:existing_value) { create(:entitlement_value, entitlement: existing_entitlement, privilege:, value: "10", organization:) }

      let(:entitlements_params) do
        {
          feature2.code => {
            privilege3.code => false
          }
        }
      end

      before do
        existing_value
      end

      it "creates a SuscriptionFeatureRemoval" do
        result
        expect(result).to be_success
        expect(existing_entitlement.reload.deleted_at).to be_nil
        expect(existing_value.reload.deleted_at).to be_nil
        expect(Entitlement::SubscriptionFeatureRemoval.where(feature:, subscription:).count).to eq(1)

        expect(Entitlement::SubscriptionEntitlement.for_subscription(subscription).pluck(:feature_code)).to eq([feature2.code])
      end
    end

    context "when subscription has an extra feature but it's not part of the params anymore" do
      let(:existing_entitlement) { create(:entitlement, organization:, plan: nil, subscription:, feature:) }
      let(:existing_value) { create(:entitlement_value, entitlement: existing_entitlement, privilege:, value: "10", organization:) }

      let(:entitlements_params) do
        {
          feature2.code => {
            privilege3.code => false
          }
        }
      end

      before do
        existing_value
      end

      it "removes the override" do
        result
        expect(result).to be_success
        expect(existing_entitlement.reload.deleted_at).to be_present
        expect(existing_value.reload.deleted_at).to be_present
        expect(Entitlement::SubscriptionFeatureRemoval.where(feature:, subscription:).count).to eq(0)

        expect(Entitlement::SubscriptionEntitlement.for_subscription(subscription).pluck(:feature_code)).to eq([feature2.code])
      end
    end

    context "when subscription has a feature override but one privilege is missing" do
      let(:entitlement) { create(:entitlement, feature: feature2, plan: nil, subscription:) }
      let(:entitlement_value2) { create(:entitlement_value, entitlement:, privilege: privilege2, value: "100") }
      let(:entitlement_value3) { create(:entitlement_value, entitlement:, privilege: privilege3, value: true) }

      let(:entitlements_params) do
        {
          feature2.code => {
            privilege3.code => false
          }
        }
      end

      before do
        entitlement_value2
        entitlement_value3
      end

      it "removes the privilege value" do
        result
        expect(entitlement_value2.reload.deleted_at).to be_present
        expect(entitlement_value3.reload.value).to eq("f")
      end
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
  end
end
