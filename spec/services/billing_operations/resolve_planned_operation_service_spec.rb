# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ResolvePlannedOperationService do
  subject(:result) { described_class.call(operation:, schedule:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) do
    create(:contract, organization:, customer:, started_at: Time.utc(2026, 2, 1), ended_at: contract_ended_at)
  end
  let(:contract_ended_at) { nil }
  let(:product) { create(:product, :fixed, organization:) }
  let(:billing_timing) { "advance" }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, proration: true) }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2026, 2, 1), billing_anchor_date: Date.new(2026, 2, 1))
  end
  let(:target_cycle_started_at) { Time.utc(2026, 2, 1) }
  let(:action_type) { "renew_fixed_advance" }
  let(:operation) do
    BillingOperation.new(
      contract_rate_card:, action_type:, billing_at: target_cycle_started_at,
      target_cycle_started_at:
    )
  end
  let(:schedule) do
    BillingOperations::BuildScheduleService.call!(contract_rate_card:).schedule
  end

  before do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1),
      billing_interval_count: 1, billing_interval_unit: "month")
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 2, 15),
      billing_interval_count: 1, billing_interval_unit: "month")
    contract_rate_card
  end

  it "resolves the first due advance operation and its successor" do
    expect(result).to be_success
    expect(result.planned_operation).to have_attributes(
      billing_at: Time.utc(2026, 2, 1),
      cycle_started_at: Time.utc(2026, 2, 1)
    )
    expect(result.planned_operation.billable_segments.map { [it.started_at, it.ended_at, it.proration_ratio] }).to eq(
      [[Time.utc(2026, 2, 1), Time.utc(2026, 2, 15), 14.fdiv(28)]]
    )
    expect(result.next_planned_operation).to have_attributes(billing_at: Time.utc(2026, 2, 15))
    expect(result.next_planned_operation.billable_segments.map(&:started_at)).to eq([Time.utc(2026, 2, 15)])
  end

  context "when billing in arrears" do
    let(:billing_timing) { "arrears" }
    let(:action_type) { "close_fixed_arrears" }
    let(:operation) do
      BillingOperation.new(
        contract_rate_card:, action_type:, billing_at: Time.utc(2026, 2, 15),
        target_cycle_started_at:
      )
    end

    it "resolves arrears slices at their own ends within the same cycle" do
      expect(result.planned_operation).to have_attributes(
        billing_at: Time.utc(2026, 2, 15),
        cycle_started_at: Time.utc(2026, 2, 1)
      )
      expect(result.next_planned_operation).to have_attributes(billing_at: Time.utc(2026, 3, 1))
      expect(result.planned_operation.billable_segments.map(&:started_at)).to eq([Time.utc(2026, 2, 1)])
      expect(result.next_planned_operation.billable_segments.map(&:started_at)).to eq([Time.utc(2026, 2, 15)])
    end
  end

  context "when the target cycle starts at the contract end" do
    let(:contract_ended_at) { Time.utc(2026, 3, 1) }
    let(:target_cycle_started_at) { contract_ended_at }

    it "returns no operation or successor" do
      expect(result).to be_success
      expect(result.planned_operation).to be_nil
      expect(result.next_planned_operation).to be_nil
    end

    context "when the target cycle starts after the contract end" do
      let(:target_cycle_started_at) { Time.utc(2026, 4, 1) }

      it "returns no operation or successor" do
        expect(result).to be_success
        expect(result.planned_operation).to be_nil
        expect(result.next_planned_operation).to be_nil
      end
    end
  end

  context "when the operation's exact billing date is no longer scheduled" do
    let(:contract_ended_at) { Time.utc(2026, 2, 10) }
    let(:action_type) { "close_fixed_arrears" }
    let(:operation) do
      BillingOperation.new(
        contract_rate_card:, action_type:, billing_at: Time.utc(2026, 3, 1),
        target_cycle_started_at:
      )
    end

    it "returns no planned operation or successor instead of choosing another slice" do
      expect(result).to be_success
      expect(result.planned_operation).to be_nil
      expect(result.next_planned_operation).to be_nil
    end
  end

  context "when resolving a contract termination operation" do
    let(:billing_timing) { "arrears" }
    let(:action_type) { "close_fixed_arrears" }
    let(:operation) do
      BillingOperation.new(
        contract_rate_card:, action_type:, causation_type: "contract_termination",
        billing_at: Time.utc(2026, 2, 20), target_cycle_started_at: Time.utc(2026, 2, 1)
      )
    end

    it "resolves the last planned group in its cycle and has no successor" do
      expect(result.planned_operation).to have_attributes(billing_at: Time.utc(2026, 3, 1))
      expect(result.next_planned_operation).to be_nil
    end
  end
end
