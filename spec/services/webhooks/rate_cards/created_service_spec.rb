# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::RateCards::CreatedService do
  subject(:create_webhook) { described_class.new(object: rate_card).call }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }

  before do
    allow(organization).to receive(:product_catalog_enabled?).and_return(true)
    create(:webhook_endpoint, organization:)
  end

  it "serializes the full card fields with empty rate and tax collections" do
    create_webhook

    expect(Webhook.order(created_at: :desc).first.payload).to eq(
      "webhook_type" => "rate_card.created",
      "object_type" => "rate_card",
      "organization_id" => organization.id,
      "rate_card" => {
        "lago_id" => rate_card.id,
        "product_code" => rate_card.product.code,
        "product_filter_code" => nil,
        "name" => rate_card.name,
        "code" => rate_card.code,
        "description" => "test description",
        "currency" => "EUR",
        "billing_timing" => "arrears",
        "proration" => false,
        "display_on_invoice" => true,
        "regroup_paid_fees" => nil,
        "applied_pricing_unit_code" => nil,
        "created_at" => rate_card.created_at.iso8601,
        "updated_at" => rate_card.updated_at.iso8601,
        "deleted_at" => nil,
        "active_rate" => nil,
        "rates" => [],
        "taxes" => []
      }
    )
  end
end
