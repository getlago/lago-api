# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::SubscriptionEntitlementDestroyService, type: :service do
  subject(:result) { described_class.call(subscription:, entitlement:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:) }
  let(:feature) { create(:feature, organization:, code: "seats") }
  let(:privilege) { create(:privilege, feature:, code: "max", value_type: "integer") }
  let(:entitlement) { create(:entitlement, subscription_external_id: subscription.external_id, plan: nil, feature:) }
  let(:entitlement_value) { create(:entitlement_value, entitlement:, privilege:, value: "30") }

  before do
    entitlement_value
  end

  it_behaves_like "a premium service"

  describe "#call" do
    around { |test| lago_premium!(&test) }

    it "returns success" do
      expect(result).to be_success
      expect(result.entitlement).to be_discarded
    end

    it "deletes the entitlement and its values" do
      expect { result }.to change(feature.entitlements, :count).by(-1)
        .and change(feature.entitlement_values, :count).by(-1)
    end

    it "sends `subscription.updated` webhook" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("subscription.updated", subscription)
    end

    it "produces an activity log" do
      subject
      expect(Utils::ActivityLog).to have_produced("subscription.updated").after_commit.with(subscription)
    end

    context "when entitlement does not exist" do
      it "returns not found failure" do
        result = described_class.call(subscription:, entitlement: nil)
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("entitlement_not_found")
      end
    end
  end
end
