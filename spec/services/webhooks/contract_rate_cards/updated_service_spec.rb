# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::ContractRateCards::UpdatedService do
  subject(:webhook_service) { described_class.new(object: contract_rate_card) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:, external_id: "contract-123") }
  let(:rate_card) { create(:rate_card, organization:, code: "api_usage") }
  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:,
      contract:,
      rate_card:,
      units: 2.5,
      effective_date: Date.new(2026, 1, 2),
      billing_anchor_date: Date.new(2026, 1, 3),
      next_billing_at: Time.zone.parse("2026-02-03T04:05:06Z")
    )
  end
  let(:phase) { create(:rate_phase, :contract_level, contract_rate_card:, code: "monthly", position: 1) }

  before do
    allow(organization).to receive(:product_catalog_enabled?).and_return(true)
    phase
    contract_rate_card.update!(
      units: 4,
      effective_date: Date.new(2026, 2, 4),
      billing_anchor_date: Date.new(2026, 2, 5),
      next_billing_at: Time.zone.parse("2026-03-06T07:08:09Z")
    )
  end

  describe ".call" do
    it "creates a webhook with every serialized updated contract rate card field" do
      webhook_service.call

      expect(Webhook.order(created_at: :desc).first.payload).to eq(
        "webhook_type" => "contract_rate_card.updated",
        "object_type" => "contract_rate_card",
        "organization_id" => organization.id,
        "contract_rate_card" => {
          "lago_id" => contract_rate_card.id,
          "external_contract_id" => "contract-123",
          "rate_card_code" => "api_usage",
          "units" => "4.0",
          "effective_date" => "2026-02-04",
          "billing_anchor_date" => "2026-02-05",
          "next_billing_at" => "2026-03-06T07:08:09Z",
          "rate_phases_count" => 1,
          "created_at" => contract_rate_card.created_at.iso8601,
          "updated_at" => contract_rate_card.updated_at.iso8601
        }
      )
    end
  end
end
