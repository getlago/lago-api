# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Plans::UpdatedDetailsService do
  subject(:webhook_service) { described_class.new(object: plan, options:) }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:options) do
    {
      changes: {
        name: {from: "Old name", to: "New name"},
        amount_cents: {from: 1000, to: 1500}
      },
      associations_changed: {
        charges: true,
        fixed_charges: false,
        taxes: false,
        usage_thresholds: false
      }
    }
  end

  describe ".call" do
    it_behaves_like "creates webhook", "plan.updated_details", "plan_updated_details", {
      "code" => String,
      "changes" => Hash,
      "associations_changed" => Hash
    }

    it "serializes only the changed fields and association flags" do
      webhook_service.call

      payload = Webhook.order(created_at: :desc).first.payload.fetch("plan_updated_details")

      expect(payload["lago_id"]).to eq(plan.id)
      expect(payload["code"]).to eq(plan.code)
      expect(payload["changes"]).to eq(
        "name" => {"from" => "Old name", "to" => "New name"},
        "amount_cents" => {"from" => 1000, "to" => 1500}
      )
      expect(payload["associations_changed"]).to eq(
        "charges" => true,
        "fixed_charges" => false,
        "taxes" => false,
        "usage_thresholds" => false
      )
    end
  end
end
