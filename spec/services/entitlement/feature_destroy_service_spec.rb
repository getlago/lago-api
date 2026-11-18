# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::FeatureDestroyService do
  subject { described_class.call(feature:) }

  let_it_be(:organization) { create(:organization) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege1) { create(:privilege, feature:, code: "max_admins", value_type: "integer") }
  let(:privilege2) { create(:privilege, feature:, code: "has_root", value_type: "boolean") }

  before do
    privilege1
    privilege2
    feature.reload
  end

  describe "#call", :premium do
    it "discards the feature" do
      expect { subject }.to change { feature.reload.discarded? }.from(false).to(true)
    end

    it "discards all privileges associated with the feature" do
      expect { subject }.to change(feature.privileges, :count).by(-2)
    end

    it "returns the feature in the result" do
      result = subject

      expect(result).to be_success
      expect(result.feature).to eq(feature)
    end

    it "sends feature.deleted webhook" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("feature.deleted", feature)
    end

    it "produces an activity log" do
      result = subject
      expect(Utils::ActivityLog).to have_produced("feature.deleted").after_commit.with(result.feature)
    end

    context "when feature is nil" do
      it "returns a not found failure" do
        result = described_class.call(feature: nil)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("feature")
      end
    end

    context "when feature is already discarded" do
      before { feature.discard! }

      it "returns a not found failure" do
        result = subject

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("feature")
      end
    end

    context "when the feature is discarded in the database after it is loaded" do
      before do
        # Another instance discards it, so the loaded one is stale.
        Entitlement::Feature.find(feature.id).discard!
      end

      it "returns a not found failure and sends no webhook" do
        result = nil
        expect { result = subject }.not_to have_enqueued_job(SendWebhookJob)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("feature")
      end
    end

    context "when a privilege is inserted after the feature is loaded" do
      let(:late_privilege) { create(:privilege, feature: Entitlement::Feature.find(feature.id), code: "late") }

      before { late_privilege }

      it "discards it with the feature" do
        expect { subject }.to change { late_privilege.reload.discarded? }.from(false).to(true)
      end
    end

    context "when a privilege create runs concurrently" do
      let(:privileges) { feature.privileges }

      before do
        # lock! reloads the feature, which drops its cached privileges relation: keep the spied one.
        allow(feature).to receive(:privileges).and_return(privileges)
        allow(feature).to receive(:lock!).and_call_original
        allow(privileges).to receive(:discard_all!).and_call_original
      end

      it "locks the feature, as the create does, before discarding its privileges" do
        subject

        expect(feature).to have_received(:lock!).ordered
        expect(privileges).to have_received(:discard_all!).ordered
      end
    end

    context "when feature has no privileges" do
      before do
        privilege1.discard!
        privilege2.discard!
      end

      it "still discards the feature successfully" do
        expect { subject }.to change { feature.reload.discarded? }.from(false).to(true)
      end
    end

    context "with removals" do
      let(:contract) { create(:contract, organization:) }
      let(:other_feature) { create(:feature, organization:) }
      let(:other_organization_feature) { create(:feature, organization: create(:organization)) }
      let(:feature_removal) { create(:subscription_feature_removal, :contract, contract:, feature:) }
      let(:privilege_removal) { create(:subscription_feature_removal, :contract, contract:, privilege: privilege1) }
      let(:other_feature_removal) { create(:subscription_feature_removal, :contract, contract:, feature: other_feature) }
      let(:other_organization_removal) { create(:subscription_feature_removal, :contract, feature: other_organization_feature) }
      let(:subscription_removal) { create(:subscription_feature_removal, feature:) }

      before do
        feature_removal
        privilege_removal
        other_feature_removal
        other_organization_removal
        subscription_removal
      end

      it "discards the contract removals of the feature and of its privileges only" do
        freeze_time do
          subject

          expect(feature_removal.reload).to have_attributes(deleted_at: Time.current, updated_at: Time.current)
          expect(privilege_removal.reload).to have_attributes(deleted_at: Time.current, updated_at: Time.current)
          expect(other_feature_removal.reload.deleted_at).to be_nil
          expect(other_organization_removal.reload.deleted_at).to be_nil
          expect(subscription_removal.reload.deleted_at).to be_nil
        end
      end
    end

    context "when feature is attached to a plan" do
      let(:entitlement) { create(:entitlement, feature:) }
      let(:privilege1_value) { create(:entitlement_value, entitlement:, privilege: privilege1, value: 10) }
      let(:privilege2_value) { create(:entitlement_value, entitlement:, privilege: privilege2, value: true) }

      before do
        privilege1_value
        privilege2_value
      end

      it "discard all values and entitlement and send webhooks" do
        expect { subject }.to change(feature.entitlement_values, :count).from(2).to(0)
          .and change(feature.entitlements, :count).from(1).to(0)
          .and have_enqueued_job(SendWebhookJob).with("feature.deleted", feature)
          .and have_enqueued_job(SendWebhookJob).with("plan.updated", entitlement.plan)
      end

      it "produces plan.updated logs" do
        subject
        expect(Utils::ActivityLog).to have_produced("plan.updated").after_commit.with(entitlement.plan)
      end
    end
  end
end
