# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::Schedule::BuildPlannedOperation do
  subject(:result) do
    described_class.call(contract_rate_card:, schedule:, timestamp:, after:)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "America/Los_Angeles") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:) }
  let(:billing_timing) { "advance" }
  let(:contract_rate_card) do
    create(
      :contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1)
    )
  end
  let(:schedule) { Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule }
  let(:timestamp) { Time.utc(2026, 11, 1) }
  let(:after) { nil }
  let(:rate_effective_from) { Time.utc(2026, 11, 1) }

  before do
    create(:rate_card_rate, organization:, rate_card:, effective_from: rate_effective_from, billing_interval_count: 1, billing_interval_unit: "month")
  end

  it "returns the first planned segment using the customer's timezone" do
    expect(result).to be_success
    expect(result.planned_operation).to have_attributes(
      cycle_started_at: Time.utc(2026, 11, 1, 7),
      billing_at: Time.utc(2026, 11, 1, 7)
    )
  end

  context "when billing in arrears" do
    let(:billing_timing) { "arrears" }

    it "plans billing at the end of the segment" do
      expect(result.planned_operation).to have_attributes(
        cycle_started_at: Time.utc(2026, 11, 1, 7),
        billing_at: Time.utc(2026, 12, 1, 8)
      )
    end
  end

  context "when regrouping paid fees" do
    let(:product) { create(:product, organization:) }
    let(:rate_card) do
      create(:rate_card, organization:, product:, billing_timing:, regroup_paid_fees: :invoice, display_on_invoice: false)
    end

    it "plans billing at the end of service" do
      expect(result.planned_operation).to have_attributes(
        cycle_started_at: Time.utc(2026, 11, 1, 7),
        billing_at: Time.utc(2026, 12, 1, 8)
      )
    end

    context "when selecting after a completed segment" do
      let(:timestamp) { Time.utc(2026, 11, 1, 7) }
      let(:after) { Time.utc(2026, 11, 15) }

      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 15), billing_interval_count: 1, billing_interval_unit: "month")
      end

      it "uses the next close's end to compare with the completed billing instant" do
        expect(result.planned_operation).to have_attributes(
          cycle_started_at: Time.utc(2026, 11, 1, 7),
          billing_at: Time.utc(2026, 12, 1, 8)
        )
      end
    end
  end

  context "when the timestamp is at the first segment boundary" do
    let(:timestamp) { Time.utc(2026, 12, 1, 8) }

    it "selects the next segment rather than reopening completed coverage" do
      expect(result.planned_operation).to have_attributes(
        cycle_started_at: Time.utc(2026, 12, 1, 8),
        billing_at: Time.utc(2026, 12, 1, 8)
      )
    end
  end

  context "when selecting an operation strictly after a completed billing instant" do
    let(:timestamp) { Time.utc(2026, 11, 1, 7) }
    let(:after) { Time.utc(2026, 11, 1, 7) }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 15), billing_interval_count: 1, billing_interval_unit: "month")
    end

    it "skips the segment due at that instant, including within the same cycle" do
      expect(result.planned_operation).to have_attributes(
        cycle_started_at: Time.utc(2026, 11, 1, 7),
        billing_at: Time.utc(2026, 11, 15)
      )
    end
  end

  context "when billing in arrears after a completed mid-cycle segment" do
    let(:billing_timing) { "arrears" }
    let(:timestamp) { Time.utc(2026, 11, 1, 7) }
    let(:after) { Time.utc(2026, 11, 15) }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 15), billing_interval_count: 1, billing_interval_unit: "month")
    end

    it "returns the next segment in the same cycle" do
      expect(result.planned_operation).to have_attributes(
        cycle_started_at: Time.utc(2026, 11, 1, 7),
        billing_at: Time.utc(2026, 12, 1, 8)
      )
    end
  end

  context "when the first price starts after the current cycle" do
    let(:rate_effective_from) { Time.utc(2026, 12, 15) }

    it "plans the first priced segment of the next billable cycle" do
      expect(result.planned_operation).to have_attributes(
        cycle_started_at: Time.utc(2026, 12, 1, 8),
        billing_at: Time.utc(2026, 12, 15)
      )
    end
  end

  context "with no schedule" do
    let(:schedule) { nil }

    it "returns no planned operation" do
      expect(result).to be_success
      expect(result.planned_operation).to be_nil
    end
  end

  context "with an exhausted schedule" do
    let(:schedule) { instance_double(Billing::RateCards::Schedule, cycle_at: nil) }

    it "returns no planned operation" do
      expect(result).to be_success
      expect(result.planned_operation).to be_nil
    end
  end

  context "when the rate card is missing" do
    let(:contract_rate_card) { nil }
    let(:schedule) { nil }

    it "returns a not found failure" do
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
