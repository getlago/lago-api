# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::BuildScheduleService do
  subject(:result) { described_class.call(contract_rate_card:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 2, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "advance", proration: true) }
  let(:contract_rate_card) do
    create(
      :contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2026, 2, 1), billing_anchor_date: Date.new(2026, 2, 1)
    )
  end

  before do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1), billing_interval_count: 1, billing_interval_unit: "month")
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 2, 15), billing_interval_count: 1, billing_interval_unit: "month")
  end

  it "builds the operation schedule using the same card calendar and pricing" do
    cycle = result.schedule.cycle_at(Time.utc(2026, 2, 1))
    billable_segments = result.schedule.billable_segments_for_cycle(cycle)

    expect(result).to be_success
    expect(result.schedule).to be_a(BillingOperations::Schedule)
    expect(billable_segments.map(&:billing_at)).to eq([Time.utc(2026, 2, 1), Time.utc(2026, 2, 15)])
    expect(billable_segments.map(&:started_at)).to eq([Time.utc(2026, 2, 1), Time.utc(2026, 2, 15)])
  end
end
