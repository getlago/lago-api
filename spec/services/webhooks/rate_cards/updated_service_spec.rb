# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::RateCards::UpdatedService do
  subject(:update_webhook) { described_class.new(object: rate_card).call }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:webhook_endpoint) { create(:webhook_endpoint, organization:) }
  let(:payload) { Webhook.find_by!(webhook_type: "rate_card.updated").payload.fetch("rate_card") }
  let(:old_tax) { create(:tax, organization:) }
  let(:new_tax) { create(:tax, organization:) }
  let(:active_rate) { create(:rate_card_rate, rate_card:, organization:, effective_from: 1.day.ago) }
  let(:future_rate) { create(:rate_card_rate, rate_card:, organization:, effective_from: 1.day.from_now) }
  let(:rates) { [active_rate, future_rate] }
  let(:taxes_before_update) { [old_tax] }
  let(:taxes_after_update) { [new_tax] }
  let(:expected_tax_ids) { [new_tax.id] }

  before do
    allow(organization).to receive(:product_catalog_enabled?).and_return(true)
    webhook_endpoint
    rates
    taxes_before_update.each do |tax|
      create(:rate_card_applied_tax, rate_card:, tax:, organization:)
    end
    rate_card.applied_taxes.destroy_all
    taxes_after_update.each do |tax|
      create(:rate_card_applied_tax, rate_card:, tax:, organization:)
    end
  end

  context "when taxes are replaced" do
    it "includes the rate timeline, active rate, and current replacement taxes" do
      update_webhook

      expect(payload.fetch("active_rate")).to include("lago_id" => active_rate.id, "code" => active_rate.code, "status" => "active")
      expect(payload.fetch("rates").map { |rate| rate.slice("lago_id", "code") }).to eq(
        rate_card.rates.map { |rate| {"lago_id" => rate.id, "code" => rate.code} }
      )
      expect(payload.fetch("taxes").map { |item| item.fetch("lago_id") }).to eq(expected_tax_ids)
    end
  end

  context "when taxes are cleared" do
    let(:taxes_after_update) { [] }
    let(:expected_tax_ids) { [] }

    it "includes the rate timeline, active rate, and empty taxes array" do
      update_webhook

      expect(payload.fetch("active_rate")).to include("lago_id" => active_rate.id, "code" => active_rate.code, "status" => "active")
      expect(payload.fetch("rates").map { |rate| rate.slice("lago_id", "code") }).to eq(
        rate_card.rates.map { |rate| {"lago_id" => rate.id, "code" => rate.code} }
      )
      expect(payload.fetch("taxes").map { |item| item.fetch("lago_id") }).to eq(expected_tax_ids)
    end
  end
end
