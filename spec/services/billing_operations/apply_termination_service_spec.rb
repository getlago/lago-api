# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ApplyTerminationService do
  subject(:result) { described_class.call(contract:, timestamp:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:old_operation) do
    create(:billing_operation, organization:, customer:, contract_rate_card:,
      action_type: "close_fixed_arrears", billing_at: Time.zone.parse("2026-02-01"),
      target_cycle_started_at: Time.zone.parse("2026-01-01"))
  end
  let(:customer) { create(:customer, organization:, timezone: nil) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "arrears", proration: false) }
  let(:timestamp) { Time.zone.parse("2026-03-01 00:00:00") }
  let(:contract) do
    create(:contract, :terminated, organization:, customer:,
      started_at: Time.zone.parse("2026-01-01 00:00:00"), terminated_at: timestamp)
  end
  let(:contract_rate_card) { card_of(contract, rate_card) }

  def card_of(contract, rate_card, effective_date: Date.new(2026, 1, 1))
    create(:contract_rate_card, organization:, contract:, rate_card:, effective_date:, billing_anchor_date: effective_date)
  end

  def priced(rate_card)
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-01-01 00:00:00"),
      billing_interval_count: 1, billing_interval_unit: "month")
    rate_card
  end

  before do
    priced(rate_card)
    contract_rate_card
  end

  context "when pending work exists" do
    before { old_operation }

    it "cancels it and creates one final operation at termination" do
      expect(result).to be_success
      expect(old_operation.reload).to have_attributes(
        cancelled_at: timestamp, cancelled_causation_type: "contract_termination",
        causation_type: "contract_activation", processed_at: nil
      )
      expect(result.billing_operations.sole).to have_attributes(
        action_type: "close_fixed_arrears", causation_type: "contract_termination",
        billing_at: timestamp, target_cycle_started_at: Time.zone.parse("2026-02-01"), processed_at: nil
      )
      expect(contract_rate_card.billing_operations.count).to eq(2)
    end
  end

  context "when completed and pending operations coexist" do
    let(:completed_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", causation_type: "contract_activation",
        billing_at: Time.zone.parse("2026-02-01"), target_cycle_started_at: Time.zone.parse("2026-01-01"),
        processed_at: Time.zone.parse("2026-02-01"))
    end
    let(:pending_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", causation_type: "contract_activation",
        billing_at: Time.zone.parse("2026-03-01"), target_cycle_started_at: Time.zone.parse("2026-02-01"))
    end

    before do
      completed_operation
      pending_operation
    end

    it "leaves completed history unchanged, cancels pending work, and creates the final operation" do
      completed_attributes = completed_operation.attributes

      expect(result).to be_success
      expect(completed_operation.reload.attributes).to eq(completed_attributes)
      expect(pending_operation.reload).to have_attributes(
        cancelled_at: timestamp, cancelled_causation_type: "contract_termination",
        causation_type: "contract_activation", processed_at: nil
      )
      expect(result.billing_operations.sole).to have_attributes(
        causation_type: "contract_termination", billing_at: timestamp,
        target_cycle_started_at: Time.zone.parse("2026-02-01")
      )
      expect(contract_rate_card.billing_operations.count).to eq(3)
    end
  end

  context "when the contract has an earlier natural end" do
    let(:timestamp) { Time.zone.parse("2026-03-01 00:00:00") }
    let(:contract) do
      create(:contract, :terminated, organization:, customer:,
        started_at: Time.zone.parse("2026-01-01"), ended_at: Time.zone.parse("2026-02-10"), terminated_at: timestamp)
    end

    it "selects the final cycle before the natural end but bills at termination" do
      expect(result).to be_success
      expect(result.billing_operations.sole).to have_attributes(
        causation_type: "contract_termination", billing_at: timestamp,
        target_cycle_started_at: Time.zone.parse("2026-02-01")
      )
    end
  end

  context "when the customer has another contract" do
    let(:other_contract) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2026-01-01")) }
    let(:other_card) { card_of(other_contract, rate_card) }
    let(:other_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card: other_card,
        action_type: "close_fixed_arrears", billing_at: Time.zone.parse("2026-02-01"),
        target_cycle_started_at: Time.zone.parse("2026-01-01"))
    end

    before { other_operation }

    it "leaves the other contract's pending operation unchanged" do
      expect(result.billing_operations.map(&:contract_rate_card_id)).to eq([contract_rate_card.id])
      expect(other_operation.reload).to have_attributes(cancelled_at: nil, processed_at: nil)
    end
  end

  context "when a card has no price" do
    before { card_of(contract, create(:rate_card, organization:)) }

    it "leaves it out instead of failing" do
      expect(result).to be_success
      expect(result.billing_operations.map(&:contract_rate_card_id)).to eq([contract_rate_card.id])
    end
  end

  context "when a card starts after the contract ends" do
    let(:future_card) do
      card_of(contract, priced(create(:rate_card, organization:)), effective_date: Date.new(2026, 4, 1))
    end
    let(:future_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card: future_card,
        billing_at: Time.zone.parse("2026-04-01"), target_cycle_started_at: Time.zone.parse("2026-04-01"))
    end

    before { future_operation }

    it "cancels its pending operation even though the card has no final operation" do
      expect(result).to be_success
      expect(future_operation.reload).to have_attributes(
        cancelled_at: timestamp, cancelled_causation_type: "contract_termination", processed_at: nil
      )
      expect(result.billing_operations.map(&:contract_rate_card_id)).to eq([contract_rate_card.id])
    end
  end

  context "when an operation targets a cycle at or after the exclusive contract end" do
    let(:end_at) { Time.zone.parse("2026-01-15") }
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at: Time.zone.parse("2026-01-01"),
        ended_at: end_at, terminated_at: timestamp)
    end
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", billing_at: end_at, target_cycle_started_at: end_at)
    end

    before { operation }

    it "cancels a cycle that begins exactly at contract end" do
      expect(result).to be_success
      expect(operation.reload).to have_attributes(
        cancelled_at: timestamp, cancelled_causation_type: "contract_termination", processed_at: nil
      )
    end
  end

  context "when termination clips a cycle split by a rate change" do
    let(:timestamp) { Time.zone.parse("2026-02-20 00:00:00") }
    let(:old_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", billing_at: Time.zone.parse("2026-03-01"),
        target_cycle_started_at: Time.zone.parse("2026-02-01"))
    end

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-02-15"),
        billing_interval_count: 1, billing_interval_unit: "month")
      old_operation
    end

    it "cancels the old operation and creates a final operation for the last surviving slice" do
      expect(result).to be_success
      expect(old_operation.reload).to have_attributes(
        cancelled_at: timestamp, cancelled_causation_type: "contract_termination", processed_at: nil
      )
      expect(result.billing_operations.sole).to have_attributes(
        causation_type: "contract_termination", action_type: "close_fixed_arrears",
        billing_at: timestamp, target_cycle_started_at: Time.zone.parse("2026-02-01")
      )
    end
  end

  context "when two arrears slices share the final cycle" do
    let(:timestamp) { Time.zone.parse("2026-01-10 00:00:00") }
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at: Time.zone.parse("2026-01-01"),
        ended_at: timestamp, terminated_at: Time.zone.parse("2026-03-01"))
    end
    let(:old_first_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", billing_at: Time.zone.parse("2026-02-01"),
        target_cycle_started_at: Time.zone.parse("2026-01-01"))
    end
    let(:old_second_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", billing_at: Time.zone.parse("2026-03-01"),
        target_cycle_started_at: Time.zone.parse("2026-01-01"))
    end

    before do
      old_first_operation
      old_second_operation
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-01-15"),
        billing_interval_count: 1, billing_interval_unit: "month")
    end

    it "cancels both old slices and creates one final operation for the surviving coverage" do
      expect(result).to be_success
      expect(old_first_operation.reload).to have_attributes(
        cancelled_at: timestamp, cancelled_causation_type: "contract_termination", processed_at: nil
      )
      expect(old_second_operation.reload).to have_attributes(
        cancelled_at: timestamp, cancelled_causation_type: "contract_termination", processed_at: nil
      )
      expect(result.billing_operations.sole).to have_attributes(
        action_type: "close_fixed_arrears", causation_type: "contract_termination",
        billing_at: timestamp, target_cycle_started_at: Time.zone.parse("2026-01-01")
      )
    end
  end

  context "when metered arrears are due at termination" do
    let(:timestamp) { Time.zone.parse("2026-02-10 00:00:00") }
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at: Time.zone.parse("2026-01-01"),
        ended_at: timestamp, terminated_at: timestamp)
    end
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:product) { create(:product, :metered, organization:, billable_metric:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "arrears") }

    it "creates one accrued-usage operation for the final cycle" do
      expect(result).to be_success
      expect(result.billing_operations.sole).to have_attributes(
        action_type: "close_metered_arrears", causation_type: "contract_termination",
        billing_at: timestamp, target_cycle_started_at: Time.zone.parse("2026-02-01")
      )
    end
  end

  context "when a fixed advance card has pending renewal slices" do
    let(:timestamp) { Time.zone.parse("2026-01-10 00:00:00") }
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at: Time.zone.parse("2026-01-01"),
        ended_at: timestamp, terminated_at: timestamp)
    end
    let(:rate_card) do
      create(:rate_card, organization:, product: create(:product, :fixed, organization:), billing_timing: "advance")
    end
    let(:pending_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "renew_fixed_advance", billing_at: Time.zone.parse("2026-01-15"),
        target_cycle_started_at: Time.zone.parse("2026-01-01"))
    end

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-01-15"),
        billing_interval_count: 1, billing_interval_unit: "month")
      pending_operation
    end

    it "cancels renewals without creating another advance charge" do
      expect(result).to be_success
      expect(pending_operation.reload).to have_attributes(
        cancelled_at: timestamp, cancelled_causation_type: "contract_termination", processed_at: nil
      )
      expect(result.billing_operations).to be_empty
    end
  end

  context "when paid advance fees are regrouped" do
    let(:timestamp) { Time.zone.parse("2026-01-10 00:00:00") }
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at: Time.zone.parse("2026-01-01"),
        ended_at: timestamp, terminated_at: timestamp)
    end
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:product) { create(:product, :metered, organization:, billable_metric:) }
    let(:rate_card) do
      create(:rate_card, :advance, organization:, product:, display_on_invoice: false, regroup_paid_fees: :invoice)
    end

    it "creates a regroup operation at termination without an additional charge" do
      expect(result).to be_success
      expect(result.billing_operations.sole).to have_attributes(
        action_type: "regroup_paid_fees", causation_type: "contract_termination", billing_at: timestamp
      )
    end
  end

  context "when recurring metered advance has pending renewals" do
    let(:timestamp) { Time.zone.parse("2026-01-10 00:00:00") }
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at: Time.zone.parse("2026-01-01"),
        ended_at: timestamp, terminated_at: timestamp)
    end
    let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
    let(:product) { create(:product, :metered, organization:, billable_metric:) }
    let(:rate_card) do
      create(:rate_card, :advance, organization:, product:, display_on_invoice: true)
    end
    let(:pending_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "renew_recurring_metered_advance", billing_at: Time.zone.parse("2026-01-15"),
        target_cycle_started_at: Time.zone.parse("2026-01-01"))
    end

    before { pending_operation }

    it "cancels the renewal without creating another advance bill" do
      expect(result).to be_success
      expect(pending_operation.reload).to have_attributes(
        cancelled_at: timestamp, cancelled_causation_type: "contract_termination", processed_at: nil
      )
      expect(result.billing_operations).to be_empty
    end
  end
end
