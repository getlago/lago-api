# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionEntitlementsUpdateService do
  subject(:result) { described_class.call(subscription:, entitlements_params:, partial: true) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:plan) { create(:plan, organization:) }
  let_it_be(:subscription) { create(:subscription, organization:, customer:, plan:) }
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
  let(:entitlement) { create(:entitlement, feature:, plan:) }
  let(:entitlement_value2) { create(:entitlement_value, entitlement:, privilege: privilege2, value: "100") }
  let(:entitlement_value3) { create(:entitlement_value, entitlement:, privilege: privilege3, value: true) }

  before do
    feature
    privilege
    entitlement_value2
    entitlement_value3
  end

  describe "#call", :premium do
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

    it "creates the entitlement with correct values and leave existing untouched" do
      result

      expect(entitlement.reload.values.map(&:value)).to contain_exactly("100", "t")
      new_entitlement = subscription.entitlements.order(:created_at).last
      expect(new_entitlement.feature).to eq(feature)
      expect(new_entitlement.values.sole.privilege).to eq privilege
      expect(new_entitlement.values.sole.value).to eq "25"
    end

    context "when subscription does not exist" do
      let(:subscription) { nil }

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("subscription_not_found")
      end
    end

    context "when a concurrent request creates the same entitlement" do
      before do
        # The concurrent request inserts its row after this one read the subscription entitlements.
        allow(Entitlement::Entitlement).to receive(:create!).and_wrap_original do |original, **attributes|
          original.call(**attributes)
          original.call(**attributes)
        end
      end

      it "returns the validation error of a taken feature" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq(feature: ["value_already_exist"])
        expect(subscription.entitlements.count).to eq(0)
        expect(SendWebhookJob).not_to have_been_enqueued
        expect(Utils::ActivityLog).not_to have_produced("subscription.updated")
      end
    end

    context "when a concurrent request creates the same entitlement value" do
      let(:sub_entitlement) { create(:entitlement, organization:, plan: nil, subscription:, feature:) }

      before do
        sub_entitlement

        # The concurrent request read the subscription entitlement before this one inserted its value.
        allow(Entitlement::SubscriptionEntitlementCoreUpdateService).to receive(:call!).and_wrap_original do |original, **kwargs|
          stale_entitlement = Entitlement::Entitlement.includes(values: :privilege).find(kwargs[:sub_entitlement].id)
          original.call(**kwargs)
          original.call(**kwargs, sub_entitlement: stale_entitlement)
        end
      end

      it "returns the validation error of a taken privilege" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(privilege: ["value_already_exist"])
        expect(sub_entitlement.values.count).to eq(0)
        expect(SendWebhookJob).not_to have_been_enqueued
      end
    end

    context "when another unique index refuses the write" do
      before do
        allow(Entitlement::Entitlement).to receive(:create!) do
          create(:plan, organization:).update_column(:code, plan.code) # rubocop:disable Rails/SkipsModelValidations
        end
      end

      it "raises the error" do
        expect { result }.to raise_error(ActiveRecord::RecordNotUnique, /index_plans_on_organization_id_and_code/)
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

    context "when value is invalid" do
      let(:entitlements_params) do
        {
          "seats" => {
            "max" => "invalid"
          }
        }
      end

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq({max_privilege_value: ["value_is_invalid"]})
      end
    end
  end
end
