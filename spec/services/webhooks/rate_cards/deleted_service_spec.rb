# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::RateCards::DeletedService do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:deleted_product) { rate_card.product }
  let(:reloaded_rate_card) { RateCard.with_discarded.find(rate_card.id) }
  let(:active_rate) { create(:rate_card_rate, rate_card:, organization:, effective_from: Time.current.beginning_of_day) }
  let(:tax) { create(:tax, organization:) }

  before do
    active_rate
    create(:rate_card_applied_tax, rate_card:, tax:, organization:)
    Products::DestroyService.call!(product: deleted_product)
    create(:webhook_endpoint, organization:)
  end

  it "serializes a deleted rate card after its product parent is discarded" do
    described_class.new(object: reloaded_rate_card).call

    webhook = Webhook.find_by!(webhook_type: "rate_card.deleted")
    expect(webhook.payload).to eq(
      "webhook_type" => "rate_card.deleted",
      "object_type" => "rate_card",
      "organization_id" => organization.id,
      "rate_card" => {
        "lago_id" => rate_card.id,
        "product_code" => deleted_product.code,
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
        "rates_count" => 0,
        "created_at" => reloaded_rate_card.created_at.iso8601,
        "updated_at" => reloaded_rate_card.updated_at.iso8601
      }
    )
  end
end
