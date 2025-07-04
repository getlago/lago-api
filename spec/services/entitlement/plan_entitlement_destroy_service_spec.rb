# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::PlanEntitlementDestroyService, type: :service do
  subject(:destroy_service) { described_class.new(entitlement: entitlement) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:feature) { create(:feature, organization:) }
  let(:privilege) { create(:privilege, organization:, feature:) }
  let(:entitlement) { create(:entitlement, organization:, plan:, feature:) }
  let(:entitlement_value) { create(:entitlement_value, entitlement:, privilege:, organization:) }

  before do
    entitlement_value
  end

  describe "#call" do
    subject(:result) { destroy_service.call }

    it "returns success" do
      expect(result).to be_success
    end

    it "soft deletes the entitlement" do
      expect { result }.to change(feature.entitlements, :count).by(-1)
    end

    it "soft deletes all entitlement values" do
      expect { result }.to change(feature.entitlement_values, :count).by(-1)
    end

    it "returns the entitlement in the result" do
      expect(result.entitlement).to eq(entitlement)
    end

    it "sends `plan.updated` webhook" do
      expect { subject }.to have_enqueued_job_after_commit(SendWebhookJob).with("plan.updated", plan)
    end

    context "when entitlement is nil" do
      subject(:result) { described_class.new(entitlement: nil).call }

      it "returns not found failure" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("entitlement_not_found")
      end
    end

    context "when entitlement is already deleted" do
      before do
        entitlement.discard!
      end

      it "still soft deletes the entitlement values" do
        expect { result }.to raise_error(Discard::RecordNotDiscarded)
      end
    end
  end
end
