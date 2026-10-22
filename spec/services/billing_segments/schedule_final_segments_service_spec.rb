# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::ScheduleFinalSegmentsService do
  subject(:result) { described_class.call(contract:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: nil) }
  let(:rate_card) { create(:rate_card, organization:, billing_timing: "arrears", proration: false) }
  let(:timestamp) { Time.zone.parse("2026-03-01 00:00:00") }

  let(:contract) do
    create(
      :contract, :terminated,
      organization:, customer:,
      started_at: Time.zone.parse("2026-01-01 00:00:00"),
      terminated_at: timestamp
    )
  end

  # Its clock is past the termination, so the clock alone would never bill it again.
  let(:contract_rate_card) { card_of(contract, rate_card, next_billing_at: Time.zone.parse("2026-04-01 00:00:00")) }

  def card_of(contract, rate_card, next_billing_at: Time.zone.parse("2026-02-01 00:00:00"), effective_date: Date.new(2026, 1, 1))
    create(
      :contract_rate_card,
      organization:, contract:, rate_card:, next_billing_at:, effective_date:,
      billing_anchor_date: effective_date
    )
  end

  def priced(rate_card)
    create(
      :rate_card_rate,
      organization:, rate_card:,
      effective_from: Time.zone.parse("2026-01-01 00:00:00"),
      billing_interval_count: 1,
      billing_interval_unit: "month"
    )
    rate_card
  end

  before do
    priced(rate_card)
    contract_rate_card
  end

  it "writes the contract's cards whatever their clock and the contract's status" do
    expect(result.billing_segments.map(&:started_at)).to eq(
      [Time.zone.parse("2026-01-01 00:00:00"), Time.zone.parse("2026-02-01 00:00:00")]
    )
  end

  it "stops the cards' clocks" do
    expect { result }.to change { contract_rate_card.reload.next_billing_at }.to(nil)
  end

  context "when the customer has another contract" do
    before { card_of(create(:contract, organization:, customer:, started_at: Time.zone.parse("2026-01-01 00:00:00")), rate_card) }

    it "leaves out its cards" do
      expect(result.billing_segments.map(&:contract_rate_card_id).uniq).to eq([contract_rate_card.id])
    end
  end

  context "when a card has no price" do
    before { card_of(contract, create(:rate_card, organization:)) }

    it "leaves it out instead of failing" do
      expect(result).to be_success
      expect(result.billing_segments.map(&:contract_rate_card_id).uniq).to eq([contract_rate_card.id])
    end
  end

  # There is no schedule to build for it: it would end before it starts.
  context "when a card starts after the contract ends" do
    before do
      card_of(
        contract, priced(create(:rate_card, organization:)),
        effective_date: Date.new(2026, 4, 1),
        next_billing_at: Time.zone.parse("2026-05-01 00:00:00")
      )
    end

    it "leaves it out instead of failing" do
      expect(result).to be_success
      expect(result.billing_segments.map(&:contract_rate_card_id).uniq).to eq([contract_rate_card.id])
    end
  end
end
