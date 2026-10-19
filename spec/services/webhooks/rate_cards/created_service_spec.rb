# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::RateCards::CreatedService do
  subject(:create_webhook) { described_class.new(object: rate_card).call }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:webhook_endpoint) { create(:webhook_endpoint, organization:) }
  let(:payload) { Webhook.find_by!(webhook_type: "rate_card.created").payload.fetch("rate_card") }
  let(:active_rate) { create(:rate_card_rate, rate_card:, organization:, effective_from: 1.day.ago) }
  let(:future_rate) { create(:rate_card_rate, rate_card:, organization:, effective_from: 1.day.from_now) }
  let(:rates) { [active_rate, future_rate] }
  let(:tax) { create(:tax, organization:) }
  let(:taxes) { [] }

  before do
    allow(organization).to receive(:product_catalog_enabled?).and_return(true)
    webhook_endpoint
    rates
    taxes.each do |rate_card_tax|
      create(:rate_card_applied_tax, rate_card:, tax: rate_card_tax, organization:)
    end
  end

  context "when the card has an active and a future rate" do
    it "includes the active rate, total rate count, and empty taxes in the webhook payload" do
      create_webhook

      expect(payload.fetch("rates_count")).to eq(2)
      expect(payload.fetch("active_rate")).to include("lago_id" => active_rate.id, "code" => active_rate.code, "status" => "active")
      expect(payload.fetch("rates").map { |rate| rate.slice("lago_id", "code") }).to eq(
        rate_card.rates.map { |rate| {"lago_id" => rate.id, "code" => rate.code} }
      )
      expect(payload.fetch("taxes")).to eq([])
    end
  end

  context "when the card has only future rates" do
    let(:rates) { [future_rate] }

    it "includes a null active rate and an empty taxes array" do
      create_webhook

      expect(payload.fetch("rates_count")).to eq(1)
      expect(payload.fetch("active_rate")).to be_nil
      expect(payload.fetch("rates").map { |rate| rate.slice("lago_id", "code") }).to eq(
        [{"lago_id" => future_rate.id, "code" => future_rate.code}]
      )
      expect(payload.fetch("taxes")).to eq([])
    end
  end

  context "when the card has taxes" do
    let(:taxes) { [tax] }

    it "includes the card's tax objects" do
      create_webhook

      expect(payload.fetch("taxes").map { |item| item.fetch("lago_id") }).to eq([tax.id])
    end
  end
end
