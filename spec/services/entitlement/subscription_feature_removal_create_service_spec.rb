# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionFeatureRemovalCreateService, type: :service do
  subject(:result) { described_class.call(subscription:, feature:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:entitlement) { create(:entitlement, organization:, plan:, feature:) }

  before do
    entitlement
  end

  it_behaves_like "a premium service"

  describe "#call" do
    around { |test| lago_premium!(&test) }

    it "returns success" do
      expect(result).to be_success
    end

    it "creates a subscription feature removal" do
      expect { result }.to change(Entitlement::SubscriptionFeatureRemoval, :count).by(1)
    end

    it "sends `subscription.updated` webhook" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("subscription.updated", subscription)
    end

    it "produces an activity log" do
      subject
      expect(Utils::ActivityLog).to have_produced("subscription.updated").after_commit.with(subscription)
    end

    it "creates the removal with correct attributes" do
      expect(Entitlement::SubscriptionEntitlement.for_subscription(subscription).map(&:code)).to eq ["seats"]

      result

      expect(Entitlement::SubscriptionEntitlement.for_subscription(subscription)).to be_empty

      removal = result.subscription_feature_removal
      expect(removal.organization).to eq(organization)
      expect(removal.feature).to eq(feature)
      expect(removal.subscription_id).to eq(subscription.id)
    end

    context "when subscription does not exist" do
      let(:subscription) { nil }

      it "returns not found failure" do
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

    context "when feature is not available in the plan" do
      let(:other_feature) { create(:feature, organization:, code: "other_feature") }

      it "returns validation failure" do
        result = described_class.call(subscription:, feature: other_feature)

        expect(result).not_to be_success
        expect(result.error).to be_a BaseService::ValidationFailure
        expect(result.error.messages[:feature]).to eq(["feature_not_available_in_plan"])
      end
    end

    context "when feature is available in parent plan" do
      let(:parent_plan) { create(:plan, organization:) }
      let(:plan) { create(:plan, organization:, parent: parent_plan) }
      let(:entitlement) { create(:entitlement, organization:, plan: parent_plan, feature:) }

      it "returns success" do
        expect(result).to be_success
      end
    end

    context "when removal already exists" do
      let(:existing_removal) { create(:subscription_feature_removal, organization:, feature:, subscription_id: subscription.id) }

      it "returns validation failure" do
        existing_removal
        expect(result).not_to be_success
        expect(result.error).to be_a BaseService::ValidationFailure
        expect(result.error.messages[:feature]).to eq(["feature_already_removed"])
      end
    end

    context "when feature is deleted from plan" do
      before do
        entitlement.update!(deleted_at: Time.current)
      end

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a BaseService::ValidationFailure
        expect(result.error.messages[:feature]).to eq(["feature_not_available_in_plan"])
      end
    end
  end
end
