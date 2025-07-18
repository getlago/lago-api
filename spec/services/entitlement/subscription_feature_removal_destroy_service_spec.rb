# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionFeatureRemovalDestroyService, type: :service do
  subject(:result) { described_class.call(subscription:, feature:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:entitlement) { create(:entitlement, plan:, feature:) }
  let(:subscription_feature_removal) { create(:subscription_feature_removal, organization:, feature:, subscription_id: subscription.id) }

  before do
    entitlement
    subscription_feature_removal
  end

  it_behaves_like "a premium service"

  describe "#call" do
    around { |test| lago_premium!(&test) }

    it "returns success" do
      all_entitlements = Entitlement::SubscriptionEntitlement.for_subscription(subscription)
      expect(all_entitlements).to be_empty
      result
      expect(all_entitlements.reload.pluck(:feature_code)).to eq ["seats"]

      expect(result).to be_success
      expect(result.subscription_feature_removal).to eq(subscription_feature_removal)
    end

    it "discards the subscription feature removal" do
      expect { result }.to change { subscription_feature_removal.reload.discarded? }.from(false).to(true)
    end

    it "sends `subscription.updated` webhook" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("subscription.updated", subscription)
    end

    it "produces an activity log" do
      subject
      expect(Utils::ActivityLog).to have_produced("subscription.updated").after_commit.with(subscription)
    end

    context "when subscription does not exist" do
      it "returns not found failure" do
        result = described_class.call(subscription: nil, feature:)
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("subscription_not_found")
      end
    end

    context "when feature does not exist" do
      it "returns not found failure" do
        result = described_class.call(subscription:, feature: nil)
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("feature_not_found")
      end
    end

    context "when removal does not exist" do
      let(:other_feature) { create(:feature, organization:, code: "other_feature") }

      it "returns not found failure" do
        result = described_class.call(subscription:, feature: other_feature)
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("subscription_feature_removal_not_found")
      end
    end

    context "when removal is already discarded" do
      before do
        subscription_feature_removal.discard!
      end

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("subscription_feature_removal_not_found")
      end
    end
  end
end
