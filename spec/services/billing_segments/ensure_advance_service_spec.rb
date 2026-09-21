# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::EnsureAdvanceService do
  subject(:result) { described_class.call(contract_rate_card:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:timestamp) { Time.zone.parse("2026-10-15 12:00:00") }
  let(:contract) do
    create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2026-11-01 10:00:00"))
  end
  let(:product) { create(:product, :metered, organization:) }
  let(:rate_card) { create(:rate_card, :advance, organization:, product:) }
  let(:contract_rate_card) do
    create(
      :contract_rate_card,
      organization:,
      contract:,
      rate_card:,
      effective_date: Date.new(2026, 11, 1),
      billing_anchor_date: Date.new(2026, 11, 1),
      next_billing_at: Time.zone.parse("2026-11-01")
    )
  end

  before do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-11-01"))
    create(:rate_phase, :contract_level, organization:, contract_rate_card:, position: 1)
  end

  it "persists the first advance segment before the contract starts" do
    expect { result }.to change(BillingSegment, :count).by(1)

    expect(result.billing_segment).to have_attributes(
      contract_rate_card:,
      status: "processing",
      started_at: Time.zone.parse("2026-11-01"),
      billing_at: Time.zone.parse("2026-11-01")
    )
  end

  it "is idempotent" do
    first_segment = result.billing_segment

    expect { described_class.call!(contract_rate_card:, timestamp:) }.not_to change(BillingSegment, :count)
    expect(described_class.call!(contract_rate_card:, timestamp:).billing_segment).to eq(first_segment)
  end

  context "with an unpriced rate card" do
    before do
      rate_card.rates.discard_all!
    end

    it "does not persist a segment" do
      expect { result }.not_to change(BillingSegment, :count)
      expect(result.billing_segment).to be_nil
    end
  end

  context "with a metered arrears rate card" do
    let(:rate_card) { create(:rate_card, organization:, product:) }

    it "does not persist a segment" do
      expect { result }.not_to change(BillingSegment, :count)
    end
  end

  context "with a fixed advance rate card" do
    let(:product) { create(:product, :fixed, organization:) }

    it "does not persist a segment" do
      expect { result }.not_to change(BillingSegment, :count)
    end
  end
end
