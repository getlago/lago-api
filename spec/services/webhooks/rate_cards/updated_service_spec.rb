# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::RateCards::UpdatedService do
  subject(:update_webhook) { described_class.new(object: rate_card).call }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:active_rate) do
    create(:rate_card_rate, rate_card:, organization:, code: "current-rate", effective_from: 1.day.ago.beginning_of_day,
      rate_properties: {"amount" => "31"})
  end

  before do
    allow(organization).to receive(:product_catalog_enabled?).and_return(true)
    create(:webhook_endpoint, organization:)
    active_rate
  end

  it "serializes the entire updated card and active rate with an empty taxes array" do
    rate_card.update!(name: "Repriced catalog", description: "Revised")
    update_webhook

    expect(Webhook.order(created_at: :desc).first.payload).to eq(
      "webhook_type" => "rate_card.updated",
      "object_type" => "rate_card",
      "organization_id" => organization.id,
      "rate_card" => {
        "lago_id" => rate_card.id,
        "product_code" => rate_card.product.code,
        "product_filter_code" => nil,
        "name" => "Repriced catalog",
        "code" => rate_card.code,
        "description" => "Revised",
        "currency" => "EUR",
        "billing_timing" => "arrears",
        "proration" => false,
        "display_on_invoice" => true,
        "regroup_paid_fees" => nil,
        "applied_pricing_unit_code" => nil,
        "rates_count" => 1,
        "created_at" => rate_card.created_at.iso8601,
        "updated_at" => rate_card.updated_at.iso8601,
        "active_rate" => {
          "lago_id" => active_rate.id,
          "code" => "current-rate",
          "rate_card_code" => rate_card.code,
          "effective_from" => active_rate.effective_from.iso8601,
          "status" => "active",
          "rate_model" => "standard",
          "rate_properties" => {"amount" => "31"},
          "min_amount_cents" => 0,
          "billing_interval_count" => 1,
          "billing_interval_unit" => "month",
          "applied_pricing_unit_conversion_rate" => nil,
          "created_at" => active_rate.created_at.iso8601,
          "updated_at" => active_rate.updated_at.iso8601
        },
        "rates" => [
          {
            "lago_id" => active_rate.id,
            "code" => "current-rate",
            "rate_card_code" => rate_card.code,
            "effective_from" => active_rate.effective_from.iso8601,
            "status" => "active",
            "rate_model" => "standard",
            "rate_properties" => {"amount" => "31"},
            "min_amount_cents" => 0,
            "billing_interval_count" => 1,
            "billing_interval_unit" => "month",
            "applied_pricing_unit_conversion_rate" => nil,
            "created_at" => active_rate.created_at.iso8601,
            "updated_at" => active_rate.updated_at.iso8601
          }
        ],
        "taxes" => []
      }
    )
  end
end
