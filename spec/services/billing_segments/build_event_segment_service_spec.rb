# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::BuildEventSegmentService do
  subject(:result) { described_class.call(contract_rate_card:, billable_segment:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:product) { create(:product, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card:, rate_properties: {"amount" => "12"}) }
  let(:cycle_started_at) { Time.zone.parse("2026-02-01") }
  let(:exclusive_end) { Time.zone.parse("2026-03-01") }
  let(:billable_segment) do
    Billing::BillableSegment.new(cycle_index: 0, cycle_started_at:, started_at: cycle_started_at,
      ended_at: exclusive_end, billing_at: exclusive_end, rate:, rate_override: nil,
      proration_ratio: 1, rate_phase_code: nil)
  end

  it "builds an in-memory slice with the priced associations and inclusive period end" do
    segment = result.billing_segment

    expect(segment).to have_attributes(
      organization:,
      customer:,
      contract:,
      contract_rate_card:,
      billable_metric_code: contract_rate_card.rate_card.product.billable_metric.code,
      rate_card_rate: rate,
      rate_properties: {"amount" => "12"},
      currency: "USD",
      cycle_started_at:,
      started_at: cycle_started_at,
      ended_at: exclusive_end - BillingSegment::MICROSECOND,
      billing_at: exclusive_end,
      proration_ratio: 1
    )
    expect(segment).not_to respond_to(:save, :reload, :persisted?)
  end

  context "with a fixed product" do
    let(:product) { create(:product, :fixed, organization:) }

    it "captures no billable metric code" do
      expect(result.billing_segment.billable_metric_code).to be_nil
    end
  end
end
