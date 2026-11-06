# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::PreviewService do
  subject(:preview) { described_class.call(contracts: [contract], from:, to:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2026-01-01")) }
  let(:rate_card) { create(:rate_card, organization:, billing_timing: "arrears", proration: false) }
  let(:from) { Time.zone.parse("2026-01-01") }
  let(:to) { Time.zone.parse("2026-04-01") }

  let!(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:,
      contract:,
      rate_card:,
      effective_date: Date.new(2026, 1, 1),
      billing_anchor_date: Date.new(2026, 1, 1),
      next_billing_at: Time.zone.parse("2026-02-01")
    )
  end

  before do
    create(
      :rate_card_rate,
      organization:,
      rate_card:,
      effective_from: Time.zone.parse("2026-01-01"),
      billing_interval_unit: "month",
      billing_interval_count: 1
    )
  end

  it "previews one segment per cycle touching the window" do
    expect(preview.previews.map { it.billable_segment.started_at.to_date }).to eq(
      [Date.new(2026, 1, 1), Date.new(2026, 2, 1), Date.new(2026, 3, 1)]
    )
  end

  it "reports the soonest instant anything bills after the window" do
    expect(preview.next_billing_at).to eq(Time.zone.parse("2026-05-01"))
  end

  it "carries the attachment each segment belongs to" do
    expect(preview.previews.map(&:contract_rate_card).uniq).to eq([contract_rate_card])
  end

  # The point of a preview: it answers from the calendar, so what has already been produced
  # makes no difference to what it shows. The stored cycle is the LAST one in the window —
  # resuming from it, as the producer does, would hide January and February.
  context "when segments have already been produced" do
    before do
      create(
        :billing_segment,
        organization:,
        customer:,
        contract:,
        contract_rate_card:,
        cycle_started_at: Time.zone.parse("2026-03-01"),
        started_at: Time.zone.parse("2026-03-01"),
        ended_at: BillingSegment.inclusive_end(Time.zone.parse("2026-04-01"))
      )
    end

    it "still previews the whole window" do
      expect(preview.previews.map { it.billable_segment.started_at.to_date }).to eq(
        [Date.new(2026, 1, 1), Date.new(2026, 2, 1), Date.new(2026, 3, 1)]
      )
    end
  end

  context "when the rate card has no rate" do
    let(:rate_card) { create(:rate_card, organization:) }

    before { RateCardRate.where(rate_card:).discard_all! }

    it "leaves the card out rather than failing" do
      expect(preview.previews).to be_empty
    end
  end

  context "when the contract is not the one asked for" do
    it "previews nothing for an unrelated contract" do
      other = create(:contract, organization:, customer:, started_at: Time.zone.parse("2026-01-01"))

      expect(described_class.call(contracts: [other], from:, to:).previews).to be_empty
    end
  end
end
