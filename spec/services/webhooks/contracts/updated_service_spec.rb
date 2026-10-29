# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Contracts::UpdatedService do
  subject(:webhook_service) { described_class.new(object: contract) }

  let(:contract) { create(:contract, external_id: "contract_external_id", name: "Original agreement", status: :active, billing_time: :calendar, billing_anchor_date: Date.new(2026, 1, 1), started_at: Time.zone.parse("2026-01-01T00:00:00Z"), consolidate_invoice: false, purchase_order_number: "PO-123", skip_invoice_custom_sections: true) }
  let(:rate_card) { create(:rate_card, organization: contract.organization, code: "standard") }
  let(:applied_rate_card) do
    create(:contract_rate_card, organization: contract.organization, contract:, rate_card:, units: 2, effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1), next_billing_at: Time.zone.parse("2026-02-01T00:00:00Z"))
  end

  before do
    allow(contract.organization).to receive(:product_catalog_enabled?).and_return(true)
    applied_rate_card
    contract.update!(name: "Updated agreement")
  end

  describe ".call" do
    it "creates a webhook with every serialized contract field" do
      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first
      expect(webhook.payload).to eq(
        "webhook_type" => "contract.updated",
        "object_type" => "contract",
        "organization_id" => contract.organization_id,
        "contract" => {
          "lago_id" => contract.id,
          "external_id" => "contract_external_id",
          "lago_customer_id" => contract.customer_id,
          "external_customer_id" => contract.customer.external_id,
          "name" => "Updated agreement",
          "plan_code" => nil,
          "status" => "active",
          "billing_time" => "calendar",
          "consolidate_invoice" => false,
          "purchase_order_number" => "PO-123",
          "billing_anchor_date" => "2026-01-01",
          "effective_billing_anchor_date" => "2026-01-01",
          "started_at" => "2026-01-01T00:00:00Z",
          "ended_at" => nil,
          "terminated_at" => nil,
          "canceled_at" => nil,
          "skip_invoice_custom_sections" => true,
          "created_at" => contract.created_at.iso8601,
          "updated_at" => contract.updated_at.iso8601,
          "applied_rate_cards" => [{
            "lago_id" => applied_rate_card.id,
            "external_contract_id" => "contract_external_id",
            "rate_card_code" => "standard",
            "units" => "2.0",
            "effective_date" => "2026-01-01",
            "billing_anchor_date" => "2026-01-01",
            "next_billing_at" => "2026-02-01T00:00:00Z",
            "created_at" => applied_rate_card.created_at.iso8601,
            "updated_at" => applied_rate_card.updated_at.iso8601,
            "deleted_at" => nil
          }]
        }
      )
    end
  end
end
