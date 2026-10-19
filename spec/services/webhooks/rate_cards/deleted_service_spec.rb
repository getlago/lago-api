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
    payload = webhook.payload.fetch("rate_card")
    expect(payload.fetch("product_code")).to be_nil
    expect(payload).to include("active_rate" => nil, "rates" => [])
    expect(payload.fetch("taxes").map { |item| item.fetch("lago_id") }).to eq([tax.id])
    expect(payload.fetch("code")).to eq(rate_card.code)
  end
end
