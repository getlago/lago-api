# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::RateCards::DeletedService do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:deleted_product) { rate_card.product }
  let(:reloaded_rate_card) { RateCard.with_discarded.find(rate_card.id) }

  before do
    Products::DestroyService.call!(product: deleted_product)
    create(:webhook_endpoint, organization:)
  end

  it "serializes a deleted rate card after its product parent is discarded" do
    described_class.new(object: reloaded_rate_card).call

    webhook = Webhook.find_by!(webhook_type: "rate_card.deleted")
    expect(webhook.payload.fetch("rate_card").fetch("product_code")).to be_nil
  end
end
