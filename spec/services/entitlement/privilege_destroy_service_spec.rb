# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::PrivilegeDestroyService do
  subject { described_class.call(privilege:) }

  let_it_be(:organization) { create(:organization) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege) { create(:privilege, feature:, code: "max_admins", value_type: "integer") }

  before do
    privilege.reload
  end

  describe "#call", :premium do
    it "discards the privilege" do
      expect { subject }.to change { privilege.reload.discarded? }.from(false).to(true)
    end

    it "returns the privilege in the result" do
      result = subject

      expect(result).to be_success
      expect(result.privilege).to eq(privilege)
    end

    it "sends feature.updated webhook" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("feature.updated", feature)
    end

    it "produces an activity log" do
      subject
      expect(Utils::ActivityLog).to have_produced("feature.updated").after_commit.with(feature)
    end

    context "when privilege is nil" do
      it "returns a not found failure" do
        result = described_class.call(privilege: nil)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("privilege")
      end
    end

    context "when the privilege is discarded between its lookup and the lock" do
      before do
        # Another instance discards it, so the loaded one is stale.
        Entitlement::Privilege.find(privilege.id).discard!
      end

      it "returns a not found failure and sends no webhook" do
        expect { subject }.not_to have_enqueued_job(SendWebhookJob)

        expect(subject).to be_failure
        expect(subject.error).to be_a(BaseService::NotFoundFailure)
        expect(subject.error.resource).to eq("privilege")
      end
    end

    context "when the feature is discarded between the lookup and the lock" do
      before do
        # Another instance discards it, so the loaded one is stale.
        Entitlement::Feature.find(feature.id).discard!
      end

      it "returns a not found failure and sends no webhook" do
        expect { subject }.not_to have_enqueued_job(SendWebhookJob)

        expect(subject).to be_failure
        expect(subject.error.resource).to eq("privilege")
        expect(Entitlement::Privilege.find(privilege.id)).not_to be_discarded
      end
    end

    context "with removals" do
      let(:contract) { create(:contract, organization:) }
      let(:other_privilege) { create(:privilege, feature:, code: "has_root", value_type: "boolean") }
      let(:privilege_removal) { create(:subscription_feature_removal, :contract, contract:, privilege:) }
      let(:other_privilege_removal) { create(:subscription_feature_removal, :contract, contract:, privilege: other_privilege) }
      let(:subscription_removal) { create(:subscription_feature_removal, privilege:) }

      before do
        privilege_removal
        other_privilege_removal
        subscription_removal
      end

      it "discards the contract removals of the privilege only" do
        freeze_time do
          expect(subject).to be_success

          expect(privilege_removal.reload).to have_attributes(deleted_at: Time.current, updated_at: Time.current)
          expect(other_privilege_removal.reload.deleted_at).to be_nil
          expect(subscription_removal.reload.deleted_at).to be_nil
        end
      end
    end

    context "when privilege has entitlements" do
      let(:entitlement) { create(:entitlement, feature:) }
      let(:entitlement_value) { create(:entitlement_value, entitlement:, privilege:, value: "10") }

      before do
        entitlement_value
      end

      it "discards all related entitlement values" do
        expect { subject }.to change(Entitlement::EntitlementValue, :count).by(-1)
      end

      it "sends `plan.updated` webhook" do
        expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan.updated", entitlement.plan)
      end

      it "produces plan.updated logs" do
        subject
        expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(entitlement.plan)
      end
    end
  end
end
