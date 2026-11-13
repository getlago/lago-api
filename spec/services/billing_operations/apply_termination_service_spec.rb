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

    it "preserves the overdue operation and creates the missing final cycle" do
      expect(result).to be_success
      expect(old_operation.reload).to have_attributes(
        cancelled_at: nil, cancelled_causation_type: nil,
        causation_type: "contract_activation", processed_at: nil
      )
      expect(result.billing_operations.sole).to have_attributes(
        action_type: "close_fixed_arrears", causation_type: "contract_termination",
        billing_at: timestamp, target_cycle_started_at: Time.zone.parse("2026-02-01"), processed_at: nil
      )
      expect(contract_rate_card.billing_operations.count).to eq(2)
    end

    it "does not duplicate obligations when termination planning is retried" do
      result
      expect { described_class.call!(contract:, timestamp:) }.not_to change(BillingOperation, :count)
      expect(old_operation.reload.cancelled_at).to be_nil
    end

    context "when the preserved close already owns several price slices" do
      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15),
          billing_interval_count: 1, billing_interval_unit: "month")
      end

      it "does not insert an earlier boundary inside the preserved coverage" do
        expect(result.billing_operations.map(&:billing_at)).to eq([timestamp])
        expect(BillingOperations::ResolveSegmentsService.call!(operation: old_operation).segments.map(&:started_at))
          .to eq([Time.utc(2026, 1, 1), Time.utc(2026, 1, 15)])
      end
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

    it "preserves history and reuses the pending operation due exactly at termination" do
      completed_attributes = completed_operation.attributes

      expect(result).to be_success
      expect(completed_operation.reload.attributes).to eq(completed_attributes)
      expect(pending_operation.reload).to have_attributes(
        cancelled_at: nil, cancelled_causation_type: nil,
        causation_type: "contract_activation", processed_at: nil
      )
      expect(result.billing_operations).to be_empty
      expect(contract_rate_card.billing_operations.count).to eq(2)
    end
  end

  context "when the final arrears operation was processed at the cycle boundary" do
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at: Time.zone.parse("2026-01-01"),
        ended_at: timestamp, terminated_at: timestamp)
    end
    let(:processed_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", causation_type: "contract_activation",
        billing_at: timestamp, target_cycle_started_at: Time.zone.parse("2026-02-01"), processed_at: timestamp)
    end

    before { processed_operation }

    it "fills the missing earlier cycle without duplicating the processed final cycle" do
      expect(result).to be_success
      expect(result.billing_operations.sole).to have_attributes(
        causation_type: "contract_termination", billing_at: Time.utc(2026, 2, 1),
        target_cycle_started_at: Time.utc(2026, 1, 1)
      )
      expect(contract_rate_card.billing_operations.count).to eq(2)
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
      expect(result.billing_operations.map(&:billing_at)).to eq([Time.utc(2026, 2, 1), timestamp])
      expect(result.billing_operations.last).to have_attributes(
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
      expect(result.billing_operations.map(&:contract_rate_card_id)).to eq([contract_rate_card.id, contract_rate_card.id])
      expect(other_operation.reload).to have_attributes(cancelled_at: nil, processed_at: nil)
    end
  end

  context "when a card has no price" do
    before { card_of(contract, create(:rate_card, organization:)) }

    it "leaves it out instead of failing" do
      expect(result).to be_success
      expect(result.billing_operations.map(&:contract_rate_card_id)).to eq([contract_rate_card.id, contract_rate_card.id])
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
      expect(result.billing_operations.map(&:contract_rate_card_id)).to eq([contract_rate_card.id, contract_rate_card.id])
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

    it "cancels the future close and creates every missing earlier and final slice" do
      expect(result).to be_success
      expect(old_operation.reload).to have_attributes(
        cancelled_at: timestamp, cancelled_causation_type: "contract_termination", processed_at: nil
      )
      expect(result.billing_operations.map(&:billing_at)).to eq([Time.utc(2026, 2, 1), Time.utc(2026, 2, 15), timestamp])
      expect(result.billing_operations.last).to have_attributes(
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

  context "when only an earlier arrears slice was processed" do
    let(:timestamp) { Time.zone.parse("2026-02-20 00:00:00") }
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at: Time.zone.parse("2026-01-01"),
        ended_at: timestamp, terminated_at: timestamp)
    end
    let(:processed_first_slice) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", causation_type: "contract_activation",
        billing_at: Time.zone.parse("2026-02-15"), target_cycle_started_at: Time.zone.parse("2026-02-01"),
        processed_at: Time.zone.parse("2026-02-15"))
    end

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2026-02-15"),
        billing_interval_count: 1, billing_interval_unit: "month")
      processed_first_slice
    end

    it "creates the termination operation for the still-due final slice" do
      expect(result).to be_success
      expect(result.billing_operations.map(&:billing_at)).to eq([Time.utc(2026, 2, 1), timestamp])
      expect(result.billing_operations.last).to have_attributes(
        action_type: "close_fixed_arrears", causation_type: "contract_termination",
        billing_at: timestamp, target_cycle_started_at: Time.zone.parse("2026-02-01")
      )
      expect(processed_first_slice.reload.processed_at).to eq(Time.zone.parse("2026-02-15"))
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

    it "creates accrued-usage operations for the missing earlier and final cycles" do
      expect(result).to be_success
      expect(result.billing_operations.map(&:billing_at)).to eq([Time.utc(2026, 2, 1), timestamp])
      expect(result.billing_operations.last).to have_attributes(
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

    it "cancels future renewals and creates the missing initial renewal" do
      expect(result).to be_success
      expect(pending_operation.reload).to have_attributes(
        cancelled_at: timestamp, cancelled_causation_type: "contract_termination", processed_at: nil
      )
      expect(result.billing_operations.sole).to have_attributes(
        action_type: "renew_fixed_advance", causation_type: "contract_termination",
        billing_at: Time.utc(2026, 1, 1), target_cycle_started_at: Time.utc(2026, 1, 1)
      )
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

    it "cancels the future renewal and creates the missing initial renewal" do
      expect(result).to be_success
      expect(pending_operation.reload).to have_attributes(
        cancelled_at: timestamp, cancelled_causation_type: "contract_termination", processed_at: nil
      )
      expect(result.billing_operations.sole).to have_attributes(
        action_type: "renew_recurring_metered_advance", causation_type: "contract_termination",
        billing_at: Time.utc(2026, 1, 1), target_cycle_started_at: Time.utc(2026, 1, 1)
      )
    end
  end

  context "when an advance renewal starts exactly at termination" do
    let(:rate_card) { create(:rate_card, :advance, organization:, product:) }
    let(:boundary_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "renew_fixed_advance", billing_at: timestamp, target_cycle_started_at: timestamp)
    end

    before { boundary_operation }

    it "cancels the renewal and creates only the missing pre-termination cycles" do
      expect(result).to be_success
      expect(boundary_operation.reload).to have_attributes(
        cancelled_at: timestamp, cancelled_causation_type: "contract_termination", processed_at: nil
      )
      expect(result.billing_operations.map { [it.target_cycle_started_at, it.billing_at] }).to eq([
        [Time.utc(2026, 1, 1), Time.utc(2026, 1, 1)],
        [Time.utc(2026, 2, 1), Time.utc(2026, 2, 1)]
      ])
    end
  end

  context "when a due same-cycle slice previously failed" do
    let(:timestamp) { Time.utc(2026, 1, 20) }
    let(:old_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", billing_at: Time.utc(2026, 1, 10),
        target_cycle_started_at: Time.utc(2026, 1, 1))
    end
    let(:processed_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", billing_at: Time.utc(2026, 1, 15),
        target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: Time.utc(2026, 1, 15))
    end

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 10))
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15))
      old_operation
      processed_operation
    end

    it "preserves its reservation even after a later slice has been processed" do
      expect(result).to be_success
      expect(old_operation.reload.cancelled_at).to be_nil
      expect(result.billing_operations.sole).to have_attributes(
        billing_at: timestamp, target_cycle_started_at: Time.utc(2026, 1, 1), causation_type: "contract_termination"
      )
      expect(BillingOperations::ResolveSegmentsService.call!(operation: old_operation).segments.map { [it.started_at, it.ended_at] })
        .to eq([[Time.utc(2026, 1, 1), BillingSegment.inclusive_end(Time.utc(2026, 1, 10))]])
      expect(BillingOperations::ResolveSegmentsService.call!(operation: result.billing_operations.sole).segments.map { [it.started_at, it.ended_at] })
        .to eq([[Time.utc(2026, 1, 15), BillingSegment.inclusive_end(timestamp)]])
    end
  end
end
