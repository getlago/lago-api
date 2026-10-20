# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::RateCards::CreatedService do
  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:, name: "Catalog card", code: "catalog-card", description: "Card description") }
  let(:active_rate) do
    create(:rate_card_rate, organization:, rate_card:, code: "base-rate", effective_from: 1.day.ago.beginning_of_day,
      rate_properties: {"amount" => "12.50"}, min_amount_cents: 500, billing_interval_count: 2)
  end
  let(:future_rate) do
    create(:rate_card_rate, organization:, rate_card:, code: "next-rate", effective_from: 1.day.from_now.beginning_of_day,
      rate_properties: {"amount" => "19"})
  end
  let(:tax) { create(:tax, organization:, name: "Sales tax", code: "sales-tax", rate: 8.25, description: "Local tax") }
  let(:active_rate_payload) do
    {
      "lago_id" => active_rate.id,
      "code" => "base-rate",
      "rate_card_code" => "catalog-card",
      "effective_from" => active_rate.effective_from.iso8601,
      "status" => "active",
      "rate_model" => "standard",
      "rate_properties" => {"amount" => "12.50"},
      "min_amount_cents" => 500,
      "billing_interval_count" => 2,
      "billing_interval_unit" => "month",
      "applied_pricing_unit_conversion_rate" => nil,
      "created_at" => active_rate.created_at.iso8601,
      "updated_at" => active_rate.updated_at.iso8601
    }
  end
  let(:future_rate_payload) do
    {
      "lago_id" => future_rate.id,
      "code" => "next-rate",
      "rate_card_code" => "catalog-card",
      "effective_from" => future_rate.effective_from.iso8601,
      "status" => "pending",
      "rate_model" => "standard",
      "rate_properties" => {"amount" => "19"},
      "min_amount_cents" => 0,
      "billing_interval_count" => 1,
      "billing_interval_unit" => "month",
      "applied_pricing_unit_conversion_rate" => nil,
      "created_at" => future_rate.created_at.iso8601,
      "updated_at" => future_rate.updated_at.iso8601
    }
  end
  let(:tax_payload) do
    {
      "lago_id" => tax.id,
      "name" => "Sales tax",
      "code" => "sales-tax",
      "rate" => 8.25,
      "description" => "Local tax",
      "applied_to_organization" => false,
      "add_ons_count" => 0,
      "customers_count" => 0,
      "plans_count" => 0,
      "charges_count" => 0,
      "commitments_count" => 0,
      "created_at" => tax.created_at.iso8601
    }
  end

  before do
    allow(organization).to receive(:product_catalog_enabled?).and_return(true)
    create(:webhook_endpoint, organization:)
  end

  describe Webhooks::RateCards::CreatedService do
    subject(:webhook_service) { described_class.new(object: rate_card) }

    before do
      active_rate
      future_rate
      create(:rate_card_applied_tax, rate_card:, tax:, organization:)
    end

    it "serializes every card, rate, and tax field for an active and future timeline" do
      webhook_service.call

      expect(Webhook.order(created_at: :desc).first.payload).to eq(
        "webhook_type" => "rate_card.created",
        "object_type" => "rate_card",
        "organization_id" => organization.id,
        "rate_card" => {
          "lago_id" => rate_card.id,
          "product_code" => rate_card.product.code,
          "product_filter_code" => nil,
          "name" => "Catalog card",
          "code" => "catalog-card",
          "description" => "Card description",
          "currency" => "EUR",
          "billing_timing" => "arrears",
          "proration" => false,
          "display_on_invoice" => true,
          "regroup_paid_fees" => nil,
          "applied_pricing_unit_code" => nil,
          "rates_count" => 2,
          "created_at" => rate_card.created_at.iso8601,
          "updated_at" => rate_card.updated_at.iso8601,
          "active_rate" => active_rate_payload,
          "rates" => [active_rate_payload, future_rate_payload],
          "taxes" => [tax_payload]
        }
      )
    end
  end

  describe Webhooks::RateCards::UpdatedService do
    subject(:webhook_service) { described_class.new(object: rate_card) }

    let(:old_tax) { create(:tax, organization:, code: "old-tax") }

    before do
      active_rate
      future_rate
      create(:rate_card_applied_tax, rate_card:, tax: old_tax, organization:)
      rate_card.update!(name: "Updated card", description: "Updated description")
      rate_card.applied_taxes.destroy_all
      create(:rate_card_applied_tax, rate_card:, tax:, organization:)
    end

    it "serializes the updated card with its complete rate timeline and replacement tax" do
      webhook_service.call

      expect(Webhook.order(created_at: :desc).first.payload).to eq(
        "webhook_type" => "rate_card.updated",
        "object_type" => "rate_card",
        "organization_id" => organization.id,
        "rate_card" => {
          "lago_id" => rate_card.id,
          "product_code" => rate_card.product.code,
          "product_filter_code" => nil,
          "name" => "Updated card",
          "code" => "catalog-card",
          "description" => "Updated description",
          "currency" => "EUR",
          "billing_timing" => "arrears",
          "proration" => false,
          "display_on_invoice" => true,
          "regroup_paid_fees" => nil,
          "applied_pricing_unit_code" => nil,
          "rates_count" => 2,
          "created_at" => rate_card.created_at.iso8601,
          "updated_at" => rate_card.updated_at.iso8601,
          "active_rate" => active_rate_payload,
          "rates" => [active_rate_payload, future_rate_payload],
          "taxes" => [tax_payload]
        }
      )
    end
  end

  describe Webhooks::RateCards::DeletedService do
    subject(:webhook_service) { described_class.new(object: rate_card) }

    before { create(:rate_card_applied_tax, rate_card:, tax:, organization:) }

    it "serializes the discarded card with nil active rate, no rates and its taxes" do
      rate_card.discard
      webhook_service.call

      expect(Webhook.order(created_at: :desc).first.payload).to eq(
        "webhook_type" => "rate_card.deleted",
        "object_type" => "rate_card",
        "organization_id" => organization.id,
        "rate_card" => {
          "lago_id" => rate_card.id,
          "product_code" => rate_card.product.code,
          "product_filter_code" => nil,
          "name" => "Catalog card",
          "code" => "catalog-card",
          "description" => "Card description",
          "currency" => "EUR",
          "billing_timing" => "arrears",
          "proration" => false,
          "display_on_invoice" => true,
          "regroup_paid_fees" => nil,
          "applied_pricing_unit_code" => nil,
          "rates_count" => 0,
          "created_at" => rate_card.created_at.iso8601,
          "updated_at" => rate_card.updated_at.iso8601,
          "active_rate" => nil,
          "rates" => [],
          "taxes" => [tax_payload]
        }
      )
    end
  end
end
