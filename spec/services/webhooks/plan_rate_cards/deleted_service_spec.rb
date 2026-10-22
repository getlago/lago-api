# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::PlanRateCards::DeletedService do
  subject(:webhook_service) { described_class.new(object: plan_rate_card) }

  let(:organization) { create(:organization) }
  let(:catalog_plan) { create(:catalog_plan, organization:, code: "starter") }
  let(:rate_card) { create(:rate_card, organization:, code: "api_usage") }
  let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, rate_card:, units: 2.5) }

  before do
    allow(organization).to receive(:product_catalog_enabled?).and_return(true)
    plan_rate_card.discard
  end

  describe ".call" do
    it "creates a webhook with every serialized discarded plan rate card field" do
      webhook_service.call

      expect(Webhook.order(created_at: :desc).first.payload).to eq(
        "webhook_type" => "plan_rate_card.deleted",
        "object_type" => "plan_rate_card",
        "organization_id" => organization.id,
        "plan_rate_card" => {
          "lago_id" => plan_rate_card.id,
          "plan_code" => "starter",
          "rate_card_code" => "api_usage",
          "units" => "2.5",
          "rate_phases_count" => 0,
          "created_at" => plan_rate_card.created_at.iso8601,
          "updated_at" => plan_rate_card.updated_at.iso8601,
          "deleted_at" => plan_rate_card.deleted_at.iso8601
        }
      )
    end
  end
end
