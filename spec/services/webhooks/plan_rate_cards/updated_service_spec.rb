# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::PlanRateCards::UpdatedService do
  subject(:webhook_service) { described_class.new(object: plan_rate_card) }

  let(:organization) { create(:organization) }
  let(:catalog_plan) { create(:catalog_plan, organization:, code: "starter") }
  let(:rate_card) { create(:rate_card, organization:, code: "api_usage") }
  let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, rate_card:, units: 2.5) }
  let(:phase) { create(:rate_phase, plan_rate_card:, code: "monthly", position: 1) }

  before do
    allow(organization).to receive(:product_catalog_enabled?).and_return(true)
    phase
    plan_rate_card.update!(units: 4)
  end

  describe ".call" do
    it "creates a webhook with every serialized updated plan rate card field" do
      webhook_service.call

      expect(Webhook.order(created_at: :desc).first.payload).to eq(
        "webhook_type" => "plan_rate_card.updated",
        "object_type" => "plan_rate_card",
        "organization_id" => organization.id,
        "plan_rate_card" => {
          "lago_id" => plan_rate_card.id,
          "plan_code" => "starter",
          "rate_card_code" => "api_usage",
          "units" => "4.0",
          "rate_phases_count" => 1,
          "created_at" => plan_rate_card.created_at.iso8601,
          "updated_at" => plan_rate_card.updated_at.iso8601
        }
      )
    end
  end
end
