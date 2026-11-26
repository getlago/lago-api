# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::SavePricingInputsService do
  subject(:result) { described_class.call(operation:, segments:) }

  let(:organization) { create(:organization) }
  let(:operation) { create(:billing_operation, organization:) }
  let(:card) { operation.contract_rate_card }
  let(:rate) { create(:rate_card_rate, organization:, rate_card: card.rate_card) }
  let(:started_at) { Time.utc(2026, 1, 15, 12, 30, 0, 123456) }
  let(:ended_at) { Time.utc(2026, 2, 1) }
  let(:segment) do
    build(:billing_segment, organization:, customer: operation.customer, contract: card.contract,
      contract_rate_card: card, rate_card_rate: rate, started_at:, ended_at: BillingSegment.inclusive_end(ended_at),
      units: 10, prepaid_units: 8, rate_properties: {"amount" => "31"}, currency: "USD", proration_ratio: BigDecimal("0.5"))
  end
  let(:segments) { [segment] }
  let(:planned_segment) do
    operation.segments.create!(organization:, position: 0, rate_card_rate: rate,
      started_at: Time.utc(2026, 1, 1), ended_at:, proration_ratio: 1)
  end

  before { planned_segment }

  it "replaces the planned segment with exact pricing inputs" do
    expect(result).to be_success
    expect(operation.segments.reload.sole).to have_attributes(
      started_at:, ended_at:, units: 10, prepaid_units: 8, rate_properties: {"amount" => "31"}, currency: "USD",
      rate_card_rate: rate, proration_ratio: BigDecimal("0.5"), position: 0
    )
  end

  context "when no coverage is billed" do
    let(:segments) { [] }

    it "retains planned coverage when there are no pricing inputs to save" do
      expect(result).to be_success
      expect(operation.segments.reload.sole.id).to eq(planned_segment.id)
      expect(operation.reload).to be_persisted
    end
  end

  context "when the replacement fails validation" do
    before { segment.rate_card_rate = nil }

    it "retains the original segment" do
      expect(result).to be_failure
      expect(operation.segments.reload.sole.id).to eq(planned_segment.id)
    end
  end
end
