# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::ContractRateCards::DeletedService do
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

  before do
    allow(organization).to receive(:product_catalog_enabled?).and_return(true)
    contract_rate_card.discard
  end

  describe ".call" do
    it "creates a webhook with every serialized discarded contract rate card field" do
      webhook_service.call

      expect(Webhook.order(created_at: :desc).first.payload).to eq(
        "webhook_type" => "contract_rate_card.deleted",
        "object_type" => "contract_rate_card",
        "organization_id" => organization.id,
        "contract_rate_card" => {
          "lago_id" => contract_rate_card.id,
          "external_contract_id" => "contract-123",
          "rate_card_code" => "api_usage",
          "units" => "2.5",
          "effective_date" => "2026-01-02",
          "billing_anchor_date" => "2026-01-03",
          "next_billing_at" => "2026-02-03T04:05:06Z",
          "rate_phases_count" => 0,
          "created_at" => contract_rate_card.created_at.iso8601,
          "updated_at" => contract_rate_card.updated_at.iso8601,
          "deleted_at" => contract_rate_card.deleted_at.iso8601
        }
      )
    end
  end
end
