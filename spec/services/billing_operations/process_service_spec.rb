# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ProcessService do
  subject(:result) { described_class.call(customer:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1), consolidate_invoice:) }
  let(:consolidate_invoice) { false }
  let(:product) { create(:product, :fixed, organization:) }
  let(:billing_timing) { "arrears" }
  let(:billing_scope) { "cycle" }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, currency: "USD", proration: true) }
  let(:rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1), rate_properties: {"amount" => "31"})
  end
  let(:cursor) { Time.utc(2026, 2, 1) }
  let(:timestamp) { cursor }
  let(:target_cycle_started_at) { Time.utc(2026, 1, 1) }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:, units: 1, next_billing_at: cursor,
      effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1))
  end
  let(:operation) do
    create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card:,
      action_type: contract_rate_card.periodic_billing_action, reason: "periodic_continuation",
      billing_at: cursor, target_cycle_started_at:)
  end

  before do
    rate
    contract_rate_card
    operation
  end

  context "with a persisted segment window" do
    let(:customer) { create(:customer, organization:, timezone: "UTC", invoice_grace_period: 3) }
    let(:operation) do
      schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule
      planned_operation = BillingOperations::Schedule::PlannedOperation.from_obligation(schedule.obligation_at(Time.utc(2026, 1, 1)))
      BillingOperations::CreateService.call!(
        contract_rate_card:, action_type: "close_fixed_arrears", reason: :periodic_continuation, planned_operation:
      ).operation
    end

    before do
      rate.update!(rate_properties: {"amount" => "100"})
      contract_rate_card.terms.first.update!(units: 3)
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15),
        rate_properties: {"amount" => "62"})
    end

    it "bills and refreshes the original plan without changing its coverage or billing again" do
      invoice = result.invoices.sole

      expect(result).to be_success
      expect(invoice).to be_draft
      expect(invoice.total_amount_cents).to eq(30_000) # Three current units at $100 on the saved rate.
      expect(invoice.fees.sole.rate_card_rate_id).to eq(rate.id)
      expect(invoice.fees.sole.properties).to include(
        "from_datetime" => Time.utc(2026, 1, 1).iso8601(6),
        "to_datetime" => BillingSegment.inclusive_end(Time.utc(2026, 2, 1)).iso8601(6)
      )
      expect(operation.reload).to have_attributes(
        coverage_started_at: Time.utc(2026, 1, 1), coverage_ended_at: Time.utc(2026, 2, 1)
      )
      expect(Invoices::RefreshDraftService.call(invoice:)).to be_success
      expect(invoice.reload.total_amount_cents).to eq(30_000) # Three current units at $100 on the saved rate.
      expect(invoice.fees.sole.rate_card_rate_id).to eq(rate.id)
      expect(invoice.fees.sole.properties).to include(
        "from_datetime" => Time.utc(2026, 1, 1).iso8601(6),
        "to_datetime" => BillingSegment.inclusive_end(Time.utc(2026, 2, 1)).iso8601(6)
      )
      expect(described_class.call!(customer:, timestamp:).invoices).to be_empty
      expect(operation.reload).to have_attributes(
        coverage_started_at: Time.utc(2026, 1, 1), coverage_ended_at: Time.utc(2026, 2, 1)
      )
    end
  end

  context "when the pending operation has no saved segments" do
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", reason: :periodic_continuation,
        billing_at: cursor, target_cycle_started_at:)
    end

    it "completes without an invoice and advances the clock" do
      expect(result).to be_success
      expect(operation.reload).to have_attributes(processed_at: timestamp, invoice_id: nil)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
      expect(customer.invoices).to be_empty
    end
  end

  context "when the last catalog rate is discarded after planning" do
    before { rate.discard! }

    it "bills the saved plan and clears the cursor" do
      invoice = result.invoices.sole

      expect(result).to be_success
      expect(invoice.total_amount_cents).to eq(3_100)
      expect(invoice.fees.sole.rate_card_rate_id).to eq(rate.id)
      expect(invoice.fees.sole.properties).to include(
        "from_datetime" => Time.utc(2026, 1, 1).iso8601(6),
        "to_datetime" => BillingSegment.inclusive_end(Time.utc(2026, 2, 1)).iso8601(6)
      )
      expect(operation.reload).to have_attributes(
        processed_at: timestamp, coverage_started_at: Time.utc(2026, 1, 1), coverage_ended_at: Time.utc(2026, 2, 1)
      )
      expect(contract_rate_card.reload.next_billing_at).to be_nil
      expect(described_class.call!(customer:, timestamp:).invoices).to be_empty
    end
  end

  it "atomically records billed coverage and advances the cursor without future operations" do
    expect(BillingOperation.count).to eq(1)
    invoice = result.invoices.sole
    expect(result).to be_success
    expect(invoice).to be_finalized
    expect(invoice.total_amount_cents).to eq(3100)
    expect(invoice.billing_operations.sole).to have_attributes(
      action_type: "close_fixed_arrears", target_cycle_started_at: Time.utc(2026, 1, 1),
      billing_at: cursor, processed_at: timestamp, customer_id: customer.id
    )
    expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    expect(contract_rate_card.billing_operations.pending).to be_empty
    expect(described_class.call!(customer:, timestamp:).invoices).to be_empty
    expect(contract_rate_card.fees.count).to eq(1)
  end

  context "with a persisted periodic continuation operation" do
    let(:periodic_operation) { operation }

    it "completes the pending operation instead of reconstructing it from the cursor" do
      invoice = result.invoices.sole

      expect(invoice.total_amount_cents).to eq(3100)
      expect(invoice.billing_operations.sole.id).to eq(periodic_operation.id)
      expect(periodic_operation.reload.processed_at).to eq(timestamp)
      expect(contract_rate_card.billing_operations.count).to eq(1)
    end
  end

  context "when a rate change splits fixed advance coverage already invoiced" do
    let(:billing_timing) { "advance" }
    let(:billing_scope) { "segment" }
    let(:target_cycle_started_at) { Time.utc(2026, 11, 1) }
    let(:cursor) { Time.utc(2026, 11, 20) }
    let(:cycle_end) { Time.utc(2026, 12, 1) }
    let(:boundary_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: cursor, rate_properties: {"amount" => "60"})
    end
    let(:operation) do
      boundary_rate
      create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card:, action_type: contract_rate_card.periodic_billing_action,
        billing_at: cursor, target_cycle_started_at:, coverage_started_at: cursor, coverage_ended_at: cycle_end)
    end
    let(:opening_operation) do
      create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card:, action_type: contract_rate_card.periodic_billing_action,
        billing_at: target_cycle_started_at, target_cycle_started_at:, coverage_started_at: target_cycle_started_at, coverage_ended_at: cursor)
    end

    around { |example| travel_to(Time.utc(2026, 11, 1)) { example.run } }

    before do
      opening_operation
      described_class.call!(customer:, timestamp: target_cycle_started_at)
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 15), rate_properties: {"amount" => "60"})
    end

    it "invoices only the days after the earlier invoice's coverage end" do
      expect(opening_operation.reload).to have_attributes(coverage_ended_at: cursor, invoice_id: be_present)
      invoice = result.invoices.sole
      expect(invoice.total_amount_cents).to eq(2_200) # $60 × 11 remaining days / 30 November days.
      expect(invoice.fees.sole.properties).to include(
        "from_datetime" => cursor.iso8601(6), "to_datetime" => BillingSegment.inclusive_end(cycle_end).iso8601(6)
      )
      expect(operation.reload).to have_attributes(coverage_started_at: cursor, coverage_ended_at: cycle_end)
    end
  end

  context "with a late payment operation" do
    let(:operation) do
      create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", reason: "late_payment",
        billing_at: cursor, target_cycle_started_at: Time.utc(2026, 1, 1))
    end

    it "processes the periodic action despite its reason" do
      expect(result.invoices.sole.total_amount_cents).to eq(3100)
      expect(operation.reload.processed_at).to eq(timestamp)
    end
  end

  context "with a pending activation operation" do
    let(:operation) { nil }
    let(:activation_operation) do
      create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
        reason: "contract_activation", billing_at: cursor, target_cycle_started_at: Time.utc(2026, 1, 1))
    end

    before { activation_operation }

    it "reuses the operation and does not create another on retry" do
      expect { result }.not_to change(BillingOperation, :count)
      expect(result.invoices.sole.billing_operations.sole.id).to eq(activation_operation.id)
      expect(activation_operation.reload).to have_attributes(processed_at: timestamp, billing_at: cursor)
      expect { described_class.call!(customer:, timestamp:) }.not_to change(BillingOperation, :count)
    end

    context "when the billing cursor has moved earlier" do
      let(:cursor) { Time.utc(2026, 1, 15) }
      let(:activation_operation) do
        create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
          reason: "contract_activation", billing_at: Time.utc(2026, 2, 1), target_cycle_started_at: Time.utc(2026, 1, 1))
      end

      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: cursor, rate_properties: {"amount" => "62"})
      end

      it "leaves a future stored operation pending instead of retiming it to the cursor" do
        expect(result.invoices).to be_empty
        expect(activation_operation.reload).to have_attributes(
          billing_at: Time.utc(2026, 2, 1), target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: nil
        )
      end
    end

    context "when the operation is not due" do
      let(:cursor) { Time.utc(2026, 3, 1) }
      let(:timestamp) { cursor - 1.second }

      it "leaves the activation operation and cursor pending" do
        expect(result.invoices).to be_empty
        expect(activation_operation.reload.processed_at).to be_nil
        expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
      end
    end

    context "when fee computation fails" do
      let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_bill") }

      before do
        allow(BillingOperations::ComputeInvoiceService).to receive(:call!).and_raise(BaseService::FailedResult.new(failure, "cannot bill"))
      end

      it "rolls back the operation and cursor for retry" do
        expect(result).to be_failure
        expect(activation_operation.reload).to have_attributes(processed_at: nil, invoice_id: nil, billing_at: cursor)
        expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
        expect(Invoice.where(customer:)).to be_empty
      end
    end

    context "when the cursor changes after the snapshot" do
      before do
        allow(described_class).to receive(:new).and_wrap_original do |original, **kwargs|
          service = original.call(**kwargs)
          allow(service).to receive(:due_operations).and_wrap_original do |load|
            load.call.to_a.tap { contract_rate_card.update!(next_billing_at: cursor + 1.day) }
          end
          service
        end
      end

      it "processes the persisted row despite a cursor change after snapshot" do
        expect(result.invoices.sole.total_amount_cents).to eq(3100)
        expect(activation_operation.reload).to have_attributes(processed_at: timestamp, billing_at: cursor)
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
      end
    end
  end

  context "when the cursor is not due yet" do
    let(:timestamp) { cursor - 1.second }

    it "does not create history or move the cursor" do
      expect(result.invoices).to be_empty
      expect(contract_rate_card.billing_operations.pending).to eq([operation])
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
    end
  end

  context "when the cursor is due without a pending operation" do
    let(:operation) { nil }

    it "does not synthesize billing history or an invoice from the cursor" do
      expect(result.invoices).to be_empty
      expect(contract_rate_card.billing_operations).to be_empty
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
    end
  end

  context "with only future, completed, or cancelled operations" do
    let(:operation) { nil }
    let(:future_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
        reason: "periodic_continuation", billing_at: cursor + 1.day,
        target_cycle_started_at: Time.utc(2026, 1, 1))
    end
    let(:completed_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
        reason: "periodic_continuation", billing_at: cursor - 1.day,
        target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: cursor - 1.day)
    end
    let(:cancelled_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
        reason: "periodic_continuation", billing_at: cursor - 1.day,
        target_cycle_started_at: Time.utc(2026, 1, 1), cancelled_at: cursor - 1.day,
        cancellation_reason: BillingOperation::CANCELLATION_REASONS.fetch(:contract_termination))
    end

    before do
      future_operation
      completed_operation
      cancelled_operation
    end

    it "does not process or synthesize work from the cursor" do
      expect { result }.not_to change(BillingOperation, :count)

      expect(result.invoices).to be_empty
      expect(future_operation.reload).to have_attributes(processed_at: nil, cancelled_at: nil)
      expect(completed_operation.reload.processed_at).to eq(cursor - 1.day)
      expect(cancelled_operation.reload).to have_attributes(processed_at: nil, cancelled_at: cursor - 1.day)
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
    end
  end

  context "with multiple overdue operations for one card" do
    let(:timestamp) { Time.utc(2026, 4, 1) }
    let(:later_operation) do
      create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", reason: "periodic_continuation",
        billing_at: Time.utc(2026, 3, 1), target_cycle_started_at: Time.utc(2026, 2, 1))
    end

    before { later_operation }

    it "processes only the earliest pending operation for that card per call" do
      invoice = result.invoices.sole

      expect(invoice.total_amount_cents).to eq(3100)
      expect(operation.reload.processed_at).to eq(timestamp)
      expect(later_operation.reload.processed_at).to be_nil
      expect(contract_rate_card.billing_operations.count).to eq(2)
    end

    context "with invoice consolidation" do
      let(:consolidate_invoice) { true }

      it "invoices the later operation's distinct coverage on the next call" do
        expect(result.invoices.sole.total_amount_cents).to eq(3100)

        expect(described_class.call!(customer:, timestamp:).invoices.sole.total_amount_cents).to eq(3100)
        expect(later_operation.reload.processed_at).to eq(timestamp)
        expect(contract_rate_card.fees.count).to eq(2)
      end
    end
  end

  context "with overdue work" do
    let(:timestamp) { Time.utc(2026, 4, 1) }

    before do
      create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
        reason: "periodic_continuation", billing_at: Time.utc(2026, 3, 1),
        target_cycle_started_at: Time.utc(2026, 2, 1))
    end

    it "processes one persisted obligation per card per call without skipping intervening cycles" do
      expect(result.invoices.sole.total_amount_cents).to eq(3100)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
      expect(described_class.call!(customer:, timestamp:).invoices.sole.total_amount_cents).to eq(3100)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 4, 1))
      expect(contract_rate_card.billing_operations.order(:billing_at).pluck(:target_cycle_started_at))
        .to eq([Time.utc(2026, 1, 1), Time.utc(2026, 2, 1)])
    end
  end

  context "when the stored cycle is unpriced but a later cycle has a price" do
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", reason: "periodic_continuation",
        billing_at: cursor, target_cycle_started_at:)
    end
    let(:rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 2, 15),
        rate_properties: {"amount" => "31"})
    end

    it "completes empty work and advances to the next priced obligation" do
      expect(result).to be_success
      expect(operation.reload).to have_attributes(processed_at: timestamp, invoice_id: nil)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
      expect(contract_rate_card.fees).to be_empty
    end
  end

  context "when the stored arrears cycle is after contract end" do
    let(:contract) do
      create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1),
        ended_at: Time.utc(2026, 1, 20))
    end
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", billing_at: cursor,
        target_cycle_started_at: Time.utc(2026, 2, 1))
    end

    it "completes empty work and clears the exhausted cursor" do
      expect(result).to be_success
      expect(operation.reload).to have_attributes(processed_at: timestamp, invoice_id: nil)
      expect(contract_rate_card.reload.next_billing_at).to be_nil
      expect(contract_rate_card.fees).to be_empty
    end
  end

  context "when another customer is due" do
    let(:other_customer) { create(:customer, organization:) }
    let(:other_contract) { create(:contract, organization:, customer: other_customer) }
    let(:other_card) { create(:contract_rate_card, organization:, contract: other_contract, rate_card:, next_billing_at: cursor) }

    before do
      other_card
      create(:billing_operation, organization:, customer: other_customer, contract_rate_card: other_card,
        action_type: "close_fixed_arrears", reason: "periodic_continuation", billing_at: cursor,
        target_cycle_started_at: Time.utc(2026, 1, 1))
    end

    it "only processes the requested customer" do
      result
      expect(other_card.reload.next_billing_at).to eq(cursor)
      expect(other_card.billing_operations.pending.count).to eq(1)
    end
  end

  context "with a due reconciliation" do
    let(:reconciliation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "reconcile_advance_coverage", reason: "rate_change",
        billing_at: cursor, target_cycle_started_at: Time.utc(2026, 1, 1))
    end

    before { reconciliation }

    it "bills the pending periodic operation while leaving reconciliation pending" do
      expect(result.invoices.sole.total_amount_cents).to eq(3100)
      expect(reconciliation.reload).to have_attributes(processed_at: nil, invoice_id: nil)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    end
  end

  context "when only a reconciliation is due" do
    let(:operation) { nil }
    let(:cursor) { Time.utc(2026, 3, 1) }
    let(:reconciliation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "reconcile_advance_coverage", reason: "rate_change",
        billing_at: Time.utc(2026, 2, 1), target_cycle_started_at: Time.utc(2026, 1, 1))
    end

    before { reconciliation }

    it "creates no invoice or history and keeps the periodic cursor" do
      expect(described_class.call!(customer:, timestamp: Time.utc(2026, 2, 1)).invoices).to be_empty
      expect(reconciliation.reload.processed_at).to be_nil
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
      expect(contract_rate_card.billing_operations).to eq([reconciliation])
    end
  end

  context "when the card is discarded" do
    before { contract_rate_card.discard! }

    it "does not bill its cursor" do
      expect(result.invoices).to be_empty
      expect(contract_rate_card.billing_operations).to eq([operation])
    end
  end

  context "when the cursor changes after the snapshot" do
    before do
      allow(described_class).to receive(:new).and_wrap_original do |original, **kwargs|
        service = original.call(**kwargs)
        allow(service).to receive(:due_operations).and_wrap_original do |load|
          load.call.to_a.tap { contract_rate_card.update!(next_billing_at: cursor + 1.day) }
        end
        service
      end
    end

    it "processes the pending operation despite a cursor change after snapshot" do
      expect(result.invoices.sole.total_amount_cents).to eq(3100)
      expect(contract_rate_card.billing_operations.sole.processed_at).to eq(timestamp)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    end
  end

  context "when an operation changes after the query snapshot" do
    let(:operation_changes) do
      {
        cancelled_at: timestamp,
        cancellation_reason: BillingOperation::CANCELLATION_REASONS.fetch(:contract_termination)
      }
    end

    before do
      allow(described_class).to receive(:new).and_wrap_original do |original, **kwargs|
        service = original.call(**kwargs)
        allow(service).to receive(:due_operations).and_wrap_original do |load|
          load.call.to_a.tap do
            # Simulate a concurrent writer without mutating the loaded snapshot record.
            # rubocop:disable Rails/SkipsModelValidations
            BillingOperation.where(id: operation.id).update_all(operation_changes)
            # rubocop:enable Rails/SkipsModelValidations
          end
        end
        service
      end
    end

    it "skips a pending operation cancelled after the snapshot" do
      expect(result.invoices).to be_empty
      expect(operation.reload).to have_attributes(processed_at: nil, cancelled_at: timestamp)
      expect(contract_rate_card.fees).to be_empty
      expect(BillingOperation.count).to eq(1)
    end

    context "when it is completed after the snapshot" do
      let(:operation_changes) { {processed_at: timestamp} }

      it "does not process the already completed operation again" do
        expect(result.invoices).to be_empty
        expect(operation.reload.processed_at).to eq(timestamp)
        expect(contract_rate_card.fees).to be_empty
        expect(BillingOperation.count).to eq(1)
      end
    end

    context "when its stored billing date changes but remains due" do
      let(:timestamp) { cursor + 1.day }
      let(:operation_changes) { {billing_at: cursor + 12.hours} }

      it "skips the operation whose billing date no longer matches the snapshot" do
        expect(result.invoices).to be_empty
        expect(operation.reload).to have_attributes(processed_at: nil, billing_at: cursor + 12.hours)
        expect(contract_rate_card.fees).to be_empty
        expect(BillingOperation.count).to eq(1)
      end
    end
  end

  context "when fee computation fails" do
    let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_bill") }

    before do
      allow(BillingOperations::ComputeInvoiceService).to receive(:call!).and_raise(BaseService::FailedResult.new(failure, "cannot bill"))
    end

    it "leaves the cursor for retry without output or history" do
      expect(result).to be_failure
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
      expect(contract_rate_card.billing_operations).to eq([operation])
      expect(Invoice.where(customer:)).to be_empty
      expect(contract_rate_card.fees).to be_empty
    end
  end

  context "when advancing the cursor fails" do
    before do
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_raise("cursor failed")
    end

    it "rolls back billing output and completed history" do
      expect { result }.to raise_error("cursor failed")
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
      expect(contract_rate_card.billing_operations).to eq([operation])
      expect(Invoice.where(customer:)).to be_empty
      expect(contract_rate_card.fees).to be_empty
    end
  end

  context "when building the next schedule fails unexpectedly" do
    before do
      allow(Billing::RateCards::BuildScheduleService).to receive(:call!).and_raise("schedule failed")
    end

    it "rolls back billing instead of clearing the cursor" do
      expect { result }.to raise_error("schedule failed")
      expect(operation.reload.processed_at).to be_nil
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
      expect(Invoice.where(customer:)).to be_empty
    end
  end

  context "when the contract ends or is terminated" do
    let(:contract) do
      create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1), consolidate_invoice:, **contract_end)
    end

    context "with a planned end at the billing date" do
      let(:contract_end) { {ended_at: Time.utc(2026, 2, 1)} }

      it "clears the cursor" do
        result
        expect(contract_rate_card.reload.next_billing_at).to be_nil
      end
    end

    context "with a termination inside the next cycle" do
      let(:contract_end) { {status: :terminated, terminated_at: Time.utc(2026, 2, 15)} }

      it "moves the cursor to the close of the remaining partial cycle" do
        result
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 2, 15))
      end
    end

    context "with a termination after the planned end" do
      let(:contract_end) { {status: :terminated, ended_at: Time.utc(2026, 2, 10), terminated_at: Time.utc(2026, 2, 15)} }

      it "moves the cursor to the final close at the termination" do
        result
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 2, 15))
      end

      context "when the close at the planned end is processed" do
        let(:cursor) { Time.utc(2026, 2, 10) }
        let(:operation) do
          create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
            reason: "periodic_continuation", billing_at: cursor, target_cycle_started_at: Time.utc(2026, 2, 1))
        end

        it "clears the cursor without scheduling the completed coverage again" do
          result
          expect(contract_rate_card.reload.next_billing_at).to be_nil
          expect(BillingOperations::ScheduleService.call!(customer:, timestamp:).billing_operations).to be_empty
          expect(described_class.call!(customer:, timestamp:).invoices).to be_empty
          expect(contract_rate_card.fees.count).to eq(1)
        end
      end

      context "when the final close is processed" do
        let(:cursor) { Time.utc(2026, 2, 15) }
        let(:operation) do
          create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
            reason: "contract_termination", billing_at: cursor, target_cycle_started_at: Time.utc(2026, 2, 1))
        end

        it "clears the cursor" do
          result
          expect(contract_rate_card.reload.next_billing_at).to be_nil
        end
      end
    end
  end

  context "with an advance renewal whose cycle starts after the contract end" do
    let(:billing_timing) { "advance" }
    let(:contract) do
      create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1), consolidate_invoice:,
        ended_at: Time.utc(2026, 2, 1))
    end
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "renew_fixed_advance",
        reason: "periodic_continuation", billing_at: cursor, target_cycle_started_at: Time.utc(2026, 2, 1))
    end

    it "completes the obsolete renewal without billing and clears the cursor" do
      expect(result.invoices).to be_empty
      expect(operation.reload).to have_attributes(
        processed_at: timestamp, invoice_id: nil,
        coverage_started_at: Time.utc(2026, 2, 1), coverage_ended_at: Time.utc(2026, 3, 1)
      )
      expect(contract_rate_card.reload.next_billing_at).to be_nil
      expect(described_class.call!(customer:, timestamp:).invoices).to be_empty
    end
  end

  context "when billing produces no fees" do
    before do
      allow(BillingOperations::ComputeInvoiceService).to receive(:call!) do |billing_segments:, **|
        double(outputs: billing_segments.index_with { [] })
      end
    end

    it "records completion and advances without an empty invoice" do
      expect(result.invoices).to be_empty
      expect(Invoice.where(customer:)).to be_empty
      expect(contract_rate_card.billing_operations.sole).to have_attributes(processed_at: timestamp, invoice_id: nil)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    end
  end

  it "finalizes only after the billing transaction commits", transaction: false do
    depth = ActiveRecord::Base.connection.open_transactions
    allow(Invoices::FinalizeContractInvoiceService).to receive(:call!) do |invoice:|
      expect(ActiveRecord::Base.connection.open_transactions).to eq(depth)
      expect(invoice.billing_operations.sole.processed_at).to eq(timestamp)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    end
    expect(result.invoices.sole).to be_generating
    expect(Invoices::FinalizeContractInvoiceService).to have_received(:call!).once
  end

  context "when finalization fails after billing commits" do
    before { allow(Invoices::FinalizeContractInvoiceService).to receive(:call!).and_raise("finalization failed") }

    it "finalizes the existing invoice on retry without repeating billing" do
      expect { result }.to raise_error("finalization failed")
      expect(contract_rate_card.billing_operations.sole.processed_at).to eq(timestamp)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
      allow(Invoices::FinalizeContractInvoiceService).to receive(:call!).and_call_original
      expect { described_class.call!(customer:, timestamp:) }
        .to not_change(Fee, :count)
        .and not_change(Invoice, :count)
        .and not_change(BillingOperation, :count)
      expect(Invoice.where(customer:).sole).to be_finalized
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    end

    context "when another customer has an unfinished invoice" do
      let(:other_customer) { create(:customer, organization:) }
      let(:other_invoice) { create(:invoice, organization:, customer: other_customer, status: :generating, invoice_type: :contract) }
      let(:other_card) { create(:contract_rate_card, organization:, contract: create(:contract, organization:, customer: other_customer)) }

      before do
        create(:billing_operation, organization:, customer: other_customer, contract_rate_card: other_card,
          invoice: other_invoice, processed_at: timestamp)
      end

      it "only recovers the current customer's invoices" do
        expect { result }.to raise_error("finalization failed")
        allow(Invoices::FinalizeContractInvoiceService).to receive(:call!).and_call_original

        described_class.call!(customer:, timestamp:)

        expect(Invoice.where(customer:).sole).to be_finalized
        expect(other_invoice.reload).to be_generating
      end
    end
  end

  context "when finalizing regrouped advance fees fails" do
    let(:product) { create(:product, organization:) }
    let(:rate_card) do
      create(:rate_card, organization:, product:, billing_timing: "advance", display_on_invoice: false,
        regroup_paid_fees: "invoice", currency: "USD")
    end
    let(:invoice) { create(:invoice, organization:, customer:, status: :generating, invoice_type: :advance_charges, total_amount_cents: 100) }
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "regroup_paid_fees",
        billing_at: cursor, target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: timestamp, invoice:)
    end

    before { allow(Invoices::FinalizeAndPublishAdvanceChargesService).to receive(:call!).and_raise("finalization failed") }

    it "retries finalization even with no pending billing operation" do
      expect { result }.to raise_error("finalization failed")
      allow(Invoices::FinalizeAndPublishAdvanceChargesService).to receive(:call!).and_call_original

      expect { described_class.call!(customer:, timestamp:) }
        .to not_change(Fee, :count).and not_change(BillingOperation, :count)
      expect(invoice.reload).to be_finalized
    end
  end

  context "with two cards on separate contracts" do
    let(:other_contract) { create(:contract, organization:, customer:, started_at: contract.started_at, consolidate_invoice:) }
    let(:other_rate_card) { rate_card }
    let(:other_billing_at) { cursor }
    let(:other_card) do
      create(:contract_rate_card, organization:, contract: other_contract, rate_card: other_rate_card, units: 1,
        next_billing_at: other_billing_at, effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1))
    end
    let(:other_operation) do
      create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card: other_card,
        action_type: "close_fixed_arrears", reason: "periodic_continuation", billing_at: other_billing_at,
        target_cycle_started_at:)
    end

    before { other_operation }

    it "keeps invoices separate for persisted operations" do
      expect(result.invoices.map(&:total_amount_cents)).to eq([3100, 3100])
    end

    context "with consolidation" do
      let(:consolidate_invoice) { true }

      it "records each card's completed operation on the shared invoice" do
        invoice = result.invoices.sole
        expect(invoice.total_amount_cents).to eq(6200) # Two $31 cards.
        expect(invoice.billing_operations.pluck(:contract_rate_card_id)).to match_array([contract_rate_card.id, other_card.id])
        expect(other_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
      end

      shared_examples "separate invoice groups" do
        it "links each operation to its own invoice" do
          expect(result).to be_success
          expect(result.invoices.size).to eq(2)
          expect(result.invoices.map { |invoice| invoice.fees.count }).to eq([1, 1])
          expect(operation.reload.invoice_id).not_to eq(other_operation.reload.invoice_id)
          expect(result.invoices.map(&:id)).to match_array([operation.invoice_id, other_operation.invoice_id])
        end
      end

      context "when billing instants fall on different customer-local dates" do
        let(:customer) { create(:customer, organization:, timezone: "America/New_York") }
        let(:target_cycle_started_at) { Time.utc(2026, 1, 1, 5) }
        let(:contract) { create(:contract, organization:, customer:, started_at: target_cycle_started_at, consolidate_invoice:) }
        let(:cursor) { Time.utc(2026, 2, 2, 4, 30) }
        let(:other_billing_at) { Time.utc(2026, 2, 2, 5, 30) }
        let(:timestamp) { other_billing_at }

        it_behaves_like "separate invoice groups"
      end

      context "when the currencies differ" do
        let(:other_rate_card) { create(:rate_card, organization:, product:, billing_timing:, currency: "EUR", proration: true) }
        let(:other_rate) do
          create(:rate_card_rate, organization:, rate_card: other_rate_card,
            effective_from: Time.utc(2026, 1, 1), rate_properties: {"amount" => "31"})
        end
        let(:other_operation) {
          other_rate
          super()
        }

        it_behaves_like "separate invoice groups"
      end

      context "when billing entities differ" do
        before { other_contract.update!(billing_entity: create(:billing_entity, organization:)) }

        it_behaves_like "separate invoice groups"
      end

      context "when purchase orders differ" do
        before do
          contract.update!(purchase_order_number: "PO-1")
          other_contract.update!(purchase_order_number: "PO-2")
        end

        it_behaves_like "separate invoice groups"

        it "sets the purchase order on each invoice" do
          expect(result.invoices.map(&:purchase_order_number)).to match_array(["PO-1", "PO-2"])
        end
      end

      context "with a default payment method" do
        let(:default_method) { create(:payment_method, organization:, customer:, is_default: true) }

        before { default_method }

        context "when the other contract explicitly selects the default" do
          before { other_contract.update!(payment_method: default_method, payment_method_type: "provider") }

          it "consolidates the operations" do
            expect(result.invoices.sole.billing_operations.pluck(:id)).to match_array([operation.id, other_operation.id])
          end
        end

        context "when the other contract explicitly selects another method" do
          let(:other_method) { create(:payment_method, organization:, customer:, is_default: false) }

          before { other_contract.update!(payment_method: other_method, payment_method_type: "provider") }

          it_behaves_like "separate invoice groups"
        end

        context "when the other contract uses manual payment" do
          before { other_contract.update!(payment_method_type: "manual") }

          it_behaves_like "separate invoice groups"
        end
      end

      context "without a default payment method" do
        before { other_contract.update!(payment_method_type: "manual") }

        it_behaves_like "separate invoice groups"
      end

      context "when both contracts select custom sections" do
        let(:first_section) { create(:invoice_custom_section, organization:) }
        let(:second_section) { create(:invoice_custom_section, organization:) }

        before do
          create(:contract_applied_invoice_custom_section, organization:, contract:, invoice_custom_section: first_section)
          create(:contract_applied_invoice_custom_section, organization:, contract: other_contract, invoice_custom_section: second_section)
        end

        it "applies both selections to the consolidated invoice" do
          expect(result.invoices.sole.applied_invoice_custom_sections.pluck(:code)).to match_array([first_section.code, second_section.code])
        end
      end

      it "loads the rates both schedules read in one query" do
        rate_queries = capture_sql { result }.grep(/FROM "rate_card_rates" WHERE.*"rate_card_id"/)

        expect(rate_queries.size).to eq(1)
      end

      it "loads terms once for the batch and bills both fixed cards" do
        queries = capture_sql { result }

        expect(result).to be_success
        expect(result.invoices.sole.total_amount_cents).to eq(6200) # Two $31 cards.
        expect(result.invoices.sole.fees.map(&:amount_cents)).to match_array([3100, 3100])
        expect(queries.grep(/SELECT .*FROM "contract_rate_cards_terms"/).size).to eq(1)
      end

      context "with custom pricing units" do
        let(:pricing_unit) { create(:pricing_unit, organization:, code: "credits") }
        let(:rate) do
          create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1),
            rate_properties: {"amount" => "31"}, applied_pricing_unit_conversion_rate: 1)
        end
        let(:rate_card) do
          create(:rate_card, organization:, product:, billing_timing:, currency: "USD", proration: true,
            applied_pricing_unit_code: pricing_unit.code)
        end

        it "loads pricing units once for all cards and builds slices without organization lookups" do
          build_queries = []
          allow(BillingSegments::BuildService).to receive(:call!).and_wrap_original do |original, **attributes|
            resolution = nil
            build_queries.concat(capture_sql { resolution = original.call(**attributes) })
            resolution
          end

          queries = capture_sql { result }

          expect(result.invoices.sole.fees.map { it.pricing_unit_usage.pricing_unit_id }).to eq([pricing_unit.id, pricing_unit.id])
          expect(queries.grep(/FROM "pricing_units"/).size).to eq(1)
          expect(build_queries.grep(/FROM "(organizations|pricing_units)"/)).to be_empty
        end
      end

      context "with filtered metered products" do
        let(:metric) { create(:sum_billable_metric, organization:, recurring: true, field_name: "units") }
        let(:product) { create(:product, organization:, billable_metric: metric) }
        let(:filter_key) { create(:billable_metric_filter, organization:, billable_metric: metric, key: "region", values: %w[eu us]) }
        let(:product_filter) { create(:product_filter, organization:, product:) }

        before do
          create(:product_filter_value, organization:, product_filter:, billable_metric_filter: filter_key, value: "eu")
          [contract, other_contract].each do |target_contract|
            create(:event, organization:, customer:, code: metric.code, external_subscription_id: target_contract.external_id,
              timestamp: Time.utc(2026, 1, 10), properties: {"units" => 1, "region" => "eu"})
          end
        end

        it "loads product filters once for all invoice targets" do
          queries = capture_sql { result }

          expect(result).to be_success
          expect(queries.grep(/FROM "product_filters"/).size).to eq(1)
        end
      end
    end
  end

  context "with two known prices in one cycle" do
    let(:billing_scope) { "segment" }
    let(:cursor) { Time.utc(2026, 1, 15) }
    let(:later_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15), rate_properties: {"amount" => "62"})
    end
    let(:operation) do
      later_rate
      create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card:,
        action_type: contract_rate_card.periodic_billing_action, reason: "periodic_continuation",
        billing_at: cursor, target_cycle_started_at:, coverage_started_at: Time.utc(2026, 1, 1),
        coverage_ended_at: Time.utc(2026, 1, 15))
    end
    let(:closing_operation) do
      create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card:, action_type: "close_fixed_arrears",
        reason: "periodic_continuation", billing_at: Time.utc(2026, 2, 1),
        target_cycle_started_at: Time.utc(2026, 1, 1),
        coverage_started_at: Time.utc(2026, 1, 15), coverage_ended_at: Time.utc(2026, 2, 1))
    end

    before do
      closing_operation
    end

    it "bills each arrears slice exactly once" do
      first_invoice = result.invoices.sole
      expect(first_invoice.total_amount_cents).to eq(1400) # $31 * 14 / 31 days.
      expect(first_invoice.fees.sole.properties).to include(
        "from_datetime" => Time.utc(2026, 1, 1).iso8601(6),
        "to_datetime" => BillingSegment.inclusive_end(Time.utc(2026, 1, 15)).iso8601(6)
      )
      expect(operation.reload).to have_attributes(invoice_id: first_invoice.id, processed_at: cursor)
      expect(first_invoice.billing_operations.pluck(:id)).to eq([operation.id])
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
      second_invoice = described_class.call!(customer:, timestamp: Time.utc(2026, 2, 1)).invoices.sole
      expect(second_invoice.total_amount_cents).to eq(3400) # $62 * 17 / 31 days.
      expect(second_invoice.fees.sole.properties).to include(
        "from_datetime" => Time.utc(2026, 1, 15).iso8601(6),
        "to_datetime" => BillingSegment.inclusive_end(Time.utc(2026, 2, 1)).iso8601(6)
      )
      expect(closing_operation.reload).to have_attributes(invoice_id: second_invoice.id, processed_at: Time.utc(2026, 2, 1))
      expect(second_invoice.billing_operations.pluck(:id)).to eq([closing_operation.id])
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
      expect(described_class.call!(customer:, timestamp: Time.utc(2026, 2, 1)).invoices).to be_empty
      expect(contract_rate_card.billing_operations.order(:billing_at).pluck(:target_cycle_started_at)).to eq([Time.utc(2026, 1, 1)] * 2)
    end

    context "with advance billing" do
      let(:billing_timing) { "advance" }
      let(:cursor) { Time.utc(2026, 1, 1) }
      let(:second_operation) do
        create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card:, action_type: "renew_fixed_advance",
          reason: "periodic_continuation", billing_at: Time.utc(2026, 1, 15),
          target_cycle_started_at: Time.utc(2026, 1, 1),
          coverage_started_at: Time.utc(2026, 1, 15), coverage_ended_at: Time.utc(2026, 2, 1))
      end

      before { second_operation }

      it "advances through both purchased slices before the next cycle" do
        first_invoice = result.invoices.sole
        expect(first_invoice.total_amount_cents).to eq(1400) # $31 * 14 / 31 days.
        expect(first_invoice.fees.sole.properties).to include(
          "from_datetime" => Time.utc(2026, 1, 1).iso8601(6),
          "to_datetime" => BillingSegment.inclusive_end(Time.utc(2026, 1, 15)).iso8601(6)
        )
        expect(operation.reload).to have_attributes(invoice_id: first_invoice.id, processed_at: cursor)
        expect(first_invoice.billing_operations.pluck(:id)).to eq([operation.id])
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 1, 15))
        second_invoice = described_class.call!(customer:, timestamp: Time.utc(2026, 1, 15)).invoices.sole
        expect(second_invoice.total_amount_cents).to eq(3400) # $62 * 17 / 31 days.
        expect(second_invoice.fees.sole.properties).to include(
          "from_datetime" => Time.utc(2026, 1, 15).iso8601(6),
          "to_datetime" => BillingSegment.inclusive_end(Time.utc(2026, 2, 1)).iso8601(6)
        )
        expect(second_operation.reload).to have_attributes(invoice_id: second_invoice.id, processed_at: Time.utc(2026, 1, 15))
        expect(second_invoice.billing_operations.pluck(:id)).to eq([second_operation.id])
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
        expect(described_class.call!(customer:, timestamp: Time.utc(2026, 1, 15)).invoices).to be_empty
      end
    end
  end

  context "when a rate is inserted after an advance operation was planned" do
    let(:billing_scope) { "segment" }
    let(:billing_timing) { "advance" }
    let(:cursor) { Time.utc(2026, 1, 1) }
    let(:operation) do
      schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule
      plan = BillingOperations::Schedule::BuildPlannedOperation.call!(schedule:, at: cursor).planned_operation
      BillingOperations::CreateService.call!(contract_rate_card:, action_type: "renew_fixed_advance",
        reason: "contract_activation", planned_operation: plan).operation
    end

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15), rate_properties: {"amount" => "62"})
    end

    it "keeps the original coverage and price despite the later split" do
      expect(operation.coverage_ended_at).to eq(Time.utc(2026, 2, 1))
      first_invoice = result.invoices.sole
      expect(first_invoice.total_amount_cents).to eq(3100)
      expect(first_invoice.fees.sole.properties).to include(
        "from_datetime" => Time.utc(2026, 1, 1).iso8601(6),
        "to_datetime" => BillingSegment.inclusive_end(Time.utc(2026, 2, 1)).iso8601(6)
      )
      expect(operation.reload).to have_attributes(
        coverage_started_at: Time.utc(2026, 1, 1), coverage_ended_at: Time.utc(2026, 2, 1)
      )
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
      expect(described_class.call!(customer:, timestamp: Time.utc(2026, 1, 15)).invoices).to be_empty
    end

    context "when cursor advancement fails" do
      before do
        allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_raise("cursor failed")
      end

      it "rolls back the corrected coverage and invoice" do
        expect { result }.to raise_error("cursor failed")
        expect(operation.reload).to have_attributes(coverage_ended_at: Time.utc(2026, 2, 1), processed_at: nil)
        expect(Invoice.where(customer:)).to be_empty
      end
    end
  end

  context "with cycle-scoped advance billing and two known prices" do
    let(:billing_timing) { "advance" }
    let(:cursor) { Time.utc(2026, 1, 1) }

    let(:later_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15),
        rate_properties: {"amount" => "62"})
    end
    let(:operation) {
      later_rate
      super()
    }

    it "purchases both priced slices once at the cycle opening" do
      invoice = result.invoices.sole

      expect(invoice.total_amount_cents).to eq(1400 + 3400) # $31 * 14/31 days, then $62 * 17/31 days.
      expect(invoice.fees.order(:amount_cents).pluck(:amount_cents)).to eq([1400, 3400])
      expect(invoice.fees.order(:amount_cents).map { |fee| fee.properties.values_at("from_datetime", "to_datetime") }).to eq([
        [Time.utc(2026, 1, 1).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 1, 15)).iso8601(6)],
        [Time.utc(2026, 1, 15).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 2, 1)).iso8601(6)]
      ])
      expect(invoice.billing_operations.sole.id).to eq(operation.id)
      expect(operation.reload.processed_at).to eq(cursor)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
      expect(described_class.call!(customer:, timestamp: Time.utc(2026, 1, 15)).invoices).to be_empty
      expect(contract_rate_card.fees.count).to eq(2)
    end
  end

  context "with cycle-scoped arrears billing and two known prices" do
    let(:later_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15),
        rate_properties: {"amount" => "62"})
    end
    let(:operation) {
      later_rate
      super()
    }

    it "bills both priced slices once at the cycle close" do
      invoice = result.invoices.sole

      expect(invoice.total_amount_cents).to eq(1400 + 3400) # $31 * 14/31 days, then $62 * 17/31 days.
      expect(invoice.fees.order(:amount_cents).pluck(:amount_cents)).to eq([1400, 3400])
      expect(invoice.fees.order(:amount_cents).map { |fee| fee.properties.values_at("from_datetime", "to_datetime") }).to eq([
        [Time.utc(2026, 1, 1).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 1, 15)).iso8601(6)],
        [Time.utc(2026, 1, 15).iso8601(6), BillingSegment.inclusive_end(Time.utc(2026, 2, 1)).iso8601(6)]
      ])
      expect(invoice.billing_operations.sole.id).to eq(operation.id)
      expect(operation.reload.processed_at).to eq(cursor)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
      expect(described_class.call!(customer:, timestamp: cursor).invoices).to be_empty
      expect(contract_rate_card.fees.count).to eq(2)
    end

    context "when computing the second fee fails" do
      let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_bill") }

      before do
        calls = 0
        allow(BillingOperations::Fees::ComputeService).to receive(:call!).and_wrap_original do |original, **attributes|
          calls += 1
          raise BaseService::FailedResult.new(failure, "cannot bill") if calls == 2

          original.call(**attributes)
        end
      end

      it "rolls back the first fee, invoice, operation and cursor" do
        expect(result).to be_failure
        expect(Invoice.where(customer:)).to be_empty
        expect(contract_rate_card.fees).to be_empty
        expect(operation.reload).to have_attributes(processed_at: nil, invoice_id: nil)
        expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
      end
    end
  end

  context "with metered arrears" do
    let(:metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
    let(:product) { create(:product, :metered, organization:, billable_metric: metric) }
    let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }

    before do
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: metric.code, timestamp: Time.utc(2026, 1, 10), properties: {})
    end

    it "records usage billing and advances its cursor" do
      expect(result.invoices.sole.fees.sole).to have_attributes(units: 1, amount_cents: 3100)
      expect(contract_rate_card.billing_operations.sole.action_type).to eq("close_metered_arrears")
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    end
  end

  context "with a draft invoice" do
    let(:customer) { create(:customer, organization:, timezone: "UTC", invoice_grace_period: 3) }

    it "enqueues draft notifications and records the expected finalization date" do
      invoice = result.invoices.sole

      expect(invoice).to have_attributes(status: "draft", expected_finalization_date: Date.new(2026, 2, 4))
      expect(operation.reload).to have_attributes(invoice_id: invoice.id, processed_at: timestamp)
      expect(SendWebhookJob).to have_been_enqueued.with("invoice.drafted", invoice)
      expect(SendWebhookJob).to have_been_enqueued.with("invoice.ready_to_finalize", invoice)
    end
  end

  context "when the contract billing entity has a grace period" do
    let(:customer) { create(:customer, organization:, timezone: "UTC", invoice_grace_period: nil) }
    let(:billing_entity) { create(:billing_entity, organization:, invoice_grace_period: 3) }

    before { contract.update!(billing_entity:) }

    it "uses that billing entity's grace period" do
      expect(result.invoices.sole).to have_attributes(
        billing_entity:, status: "draft", expected_finalization_date: Date.new(2026, 2, 4)
      )
    end
  end

  context "with invoice custom sections" do
    let(:section) { create(:invoice_custom_section, organization:) }

    context "when the contract selects a section" do
      before { create(:contract_applied_invoice_custom_section, organization:, contract:, invoice_custom_section: section) }

      it "copies the selection onto the invoice" do
        expect(result.invoices.sole.applied_invoice_custom_sections.pluck(:code)).to eq([section.code])
      end
    end

    context "when the contract has no selection" do
      before do
        create(:billing_entity_applied_invoice_custom_section, organization:,
          billing_entity: customer.billing_entity, invoice_custom_section: section)
      end

      it "uses the customer billing entity's fallback" do
        expect(result.invoices.sole.applied_invoice_custom_sections.pluck(:code)).to eq([section.code])
      end

      context "when the contract skips sections" do
        before { contract.update!(skip_invoice_custom_sections: true) }

        it "does not apply the fallback" do
          expect(result.invoices.sole.applied_invoice_custom_sections).to be_empty
        end
      end
    end
  end

  context "with metered arrears and a grace period" do
    let(:customer) { create(:customer, organization:, timezone: "UTC", invoice_grace_period: 3) }
    let(:metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
    let(:product) { create(:product, :metered, organization:, billable_metric: metric) }
    let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
    let(:late_event) do
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: metric.code, timestamp: Time.utc(2026, 1, 10), properties: {})
    end
    let(:outside_events) do
      [Time.utc(2025, 12, 31), Time.utc(2026, 2, 2)].each do |event_time|
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: metric.code, timestamp: event_time, properties: {})
      end
    end

    around { |example| travel_to(Time.utc(2026, 2, 1, 12)) { example.run } }

    before { outside_events }

    it "keeps an empty draft and refreshes its original coverage when late usage arrives" do
      invoice = result.invoices.sole
      expect(invoice).to be_draft
      expect(invoice.fees).to be_empty
      expect(operation.reload).to have_attributes(invoice_id: invoice.id, processed_at: timestamp)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))

      late_event
      expect(Invoices::RefreshDraftService.call(invoice:)).to be_success
      expect(invoice.reload.fees.sole).to have_attributes(units: 1, amount_cents: 3100)
      expect(invoice.total_amount_cents).to eq(3100)
      expect(invoice.billing_operations.pluck(:id)).to eq([operation.id])
      expect(Invoice.where(customer:).pluck(:id)).to eq([invoice.id])
      expect(BillingOperation.count).to eq(1)
    end

    context "without a grace period" do
      let(:customer) { create(:customer, organization:, timezone: "UTC", invoice_grace_period: 0) }

      it "completes an empty operation without an invoice" do
        expect(result.invoices).to be_empty
        expect(operation.reload).to have_attributes(invoice_id: nil, processed_at: timestamp)
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
      end
    end

    context "with a consolidated priced card" do
      let(:consolidate_invoice) { true }
      let(:fixed_product) { create(:product, :fixed, organization:) }
      let(:fixed_rate_card) { create(:rate_card, organization:, product: fixed_product, currency: "USD", proration: true) }
      let(:fixed_card) do
        create(:contract_rate_card, organization:, contract:, rate_card: fixed_rate_card, units: 1,
          next_billing_at: cursor, effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1))
      end
      let(:fixed_operation) do
        create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card: fixed_card,
          action_type: "close_fixed_arrears", reason: "periodic_continuation",
          billing_at: cursor, target_cycle_started_at: Time.utc(2026, 1, 1))
      end

      before do
        create(:rate_card_rate, organization:, rate_card: fixed_rate_card,
          effective_from: Time.utc(2026, 1, 1), rate_properties: {"amount" => "31"})
        fixed_operation
      end

      it "refreshes both covered operations without billing adjacent cycles" do
        invoice = result.invoices.sole
        expect(invoice).to be_draft
        expect(invoice.total_amount_cents).to eq(3100)
        expect(invoice.billing_operations.pluck(:id)).to match_array([operation.id, fixed_operation.id])
        expect(invoice.fees.sole.contract_rate_card_id).to eq(fixed_card.id)

        late_event
        expect(Invoices::RefreshDraftService.call(invoice:)).to be_success
        expect(invoice.reload.total_amount_cents).to eq(6200) # $31 fixed + one $31 usage event.
        expect(invoice.fees.order(:amount_cents).pluck(:contract_rate_card_id)).to match_array([contract_rate_card.id, fixed_card.id])
        expect(invoice.fees.find_by!(contract_rate_card:).units).to eq(1)
        expect(invoice.billing_operations.pluck(:id)).to match_array([operation.id, fixed_operation.id])
        expect(Invoice.where(customer:).pluck(:id)).to eq([invoice.id])
        expect(BillingOperation.count).to eq(2)
      end

      context "without a grace period" do
        let(:customer) { create(:customer, organization:, timezone: "UTC", invoice_grace_period: 0) }

        it "links only the operation that produced a fee" do
          invoice = result.invoices.sole
          expect(invoice).to be_finalized
          expect(invoice.billing_operations.pluck(:id)).to eq([fixed_operation.id])
          expect(operation.reload).to have_attributes(invoice_id: nil, processed_at: timestamp)
        end
      end

      context "with an obsolete renewal in the batch" do
        let(:ended_contract) do
          create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1),
            ended_at: cursor, consolidate_invoice: true)
        end
        let(:advance_rate_card) { create(:rate_card, :advance, organization:, product: fixed_product, currency: "USD") }
        let(:ended_card) do
          create(:contract_rate_card, organization:, contract: ended_contract, rate_card: advance_rate_card,
            next_billing_at: cursor, effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1))
        end
        let(:obsolete_operation) do
          create(:billing_operation, organization:, customer:, contract_rate_card: ended_card,
            action_type: "renew_fixed_advance", reason: "periodic_continuation",
            billing_at: cursor, target_cycle_started_at: cursor)
        end

        before { obsolete_operation }

        it "does not link an operation with no resolved coverage" do
          invoice = result.invoices.sole
          expect(invoice.billing_operations.pluck(:id)).to match_array([operation.id, fixed_operation.id])
          expect(obsolete_operation.reload).to have_attributes(invoice_id: nil, processed_at: timestamp)
          expect(ended_card.reload.next_billing_at).to be_nil
        end
      end
    end
  end

  context "with recurring metered advance" do
    let(:cursor) { Time.utc(2026, 1, 1) }
    let(:metric) { create(:sum_billable_metric, organization:, recurring: true, field_name: "quantity") }
    let(:product) { create(:product, :metered, organization:, billable_metric: metric) }
    let(:rate_card) { create(:rate_card, :advance, organization:, product:, currency: "USD", display_on_invoice: true) }

    it "records a no-output renewal and advances" do
      expect(result.invoices).to be_empty
      expect(contract_rate_card.billing_operations.sole).to have_attributes(action_type: "renew_recurring_metered_advance", processed_at: timestamp)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
    end
  end

  context "with paid advance fees to regroup" do
    let(:metric) { create(:billable_metric, organization:) }
    let(:product) { create(:product, :metered, organization:, billable_metric: metric) }
    let(:rate_card) do
      create(:rate_card, :advance, organization:, product:, currency: "USD", display_on_invoice: false, regroup_paid_fees: :invoice)
    end
    let(:paid_fee) do
      billing_segment = BillingOperations::ResolveSegmentsService.call!(operation:).billing_segments.sole
      metered_item = Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment:)
      create(:fee, :succeeded, invoice: nil, subscription: nil, organization:, billing_entity: customer.billing_entity,
        contract:, contract_rate_card:, rate_card_rate: rate, invoiceable: product, fee_type: :product,
        amount_currency: "USD", amount_cents: 500, pay_in_advance: true, succeeded_at: Time.utc(2026, 1, 10),
        properties: metered_item.filtered_for_charge_boundaries)
    end

    before { paid_fee }

    it "attaches the paid fee without charging again" do
      expect(result.invoices.sole.fees).to eq([paid_fee])
      expect(contract_rate_card.billing_operations.sole.invoice_id).to eq(paid_fee.reload.invoice_id)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
      expect(described_class.call!(customer:, timestamp:).invoices).to be_empty
    end

    context "when cycle billing spans two rates" do
      let(:second_rate) do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15),
          rate_properties: {"amount" => "2"})
      end
      let(:operation) do
        second_rate
        super()
      end
      let(:paid_fees) do
        BillingOperations::ResolveSegmentsService.call!(operation:).billing_segments.each_with_index.map do |segment, index|
          metered_item = Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: segment)
          create(:fee, :succeeded, invoice: nil, subscription: nil, organization:, billing_entity: customer.billing_entity,
            contract:, contract_rate_card:, rate_card_rate: segment.rate_card_rate, invoiceable: product, fee_type: :product,
            amount_currency: "USD", amount_cents: (index + 1) * 500, taxes_amount_cents: 0, pay_in_advance: true,
            succeeded_at: segment.started_at + 1.day, properties: metered_item.filtered_for_charge_boundaries)
        end
      end
      let(:paid_fee) { paid_fees.first }
      let(:unpaid_fee) do
        create(:fee, invoice: nil, subscription: nil, organization:, billing_entity: customer.billing_entity,
          contract:, contract_rate_card:, rate_card_rate: second_rate, invoiceable: product, fee_type: :product,
          amount_currency: "USD", amount_cents: 700, pay_in_advance: true, payment_status: :pending,
          properties: paid_fees.last.properties)
      end

      before { unpaid_fee }

      it "regroups both paid segments on one invoice without duplicating fees or including an unpaid fee" do
        expect { result }.not_to change(Fee, :count)

        invoice = result.invoices.sole
        expect(invoice).to have_attributes(total_amount_cents: 500 + 1000, payment_status: "succeeded")
        expect(invoice.fees).to match_array(paid_fees)
        expect(invoice.fees.pluck(:rate_card_rate_id)).to match_array([rate.id, second_rate.id])
        expect(unpaid_fee.reload.invoice_id).to be_nil
        expect(operation.reload).to have_attributes(invoice_id: invoice.id, processed_at: timestamp)
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
        expect(described_class.call!(customer:, timestamp:).invoices).to be_empty
        expect(invoice.reload.fees).to match_array(paid_fees)
      end
    end
  end
end
