# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ProcessService do
  describe ".call" do
    subject(:result) { described_class.call(customer:, timestamp:) }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:contract) { create(:contract, organization:, customer:) }
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
    let(:timestamp) { Time.current.change(usec: 0) }
    let(:action_type) { "reconcile_advance_coverage" }
    let(:billing_at) { timestamp - 1.day }
    let(:operation) do
      create(
        :billing_operation,
        organization:,
        customer:,
        contract_rate_card:,
        action_type:,
        billing_at:,
        target_cycle_started_at: timestamp.beginning_of_month
      )
    end

    it "leaves an ineligible reconciliation pending without creating billing output" do
      operation

      expect(result).to be_success
      expect(operation.reload.processed_at).to be_nil
      expect(operation.invoice_id).to be_nil
      expect(Invoice.where(customer:)).to be_empty
    end

    context "when the operation is cancelled" do
      let(:action_type) { "close_fixed_arrears" }
      let(:operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:, action_type:,
          billing_at:, target_cycle_started_at: timestamp.beginning_of_month,
          cancelled_at: timestamp, cancelled_causation_type: :contract_termination)
      end

      it "does not bill or create a successor when explicitly invoked" do
        operation

        expect(result).to be_success
        expect(result.invoices).to be_empty
        expect(operation.reload).to have_attributes(cancelled_at: timestamp, processed_at: nil)
        expect(contract_rate_card.billing_operations.count).to eq(1)
      end
    end

    context "when a snapshotted operation changes before its row lock" do
      let(:action_type) { "close_fixed_arrears" }

      before do
        operation
        allow(described_class).to receive(:new).and_wrap_original do |original, *args, **kwargs|
          service = original.call(*args, **kwargs)
          allow(service).to receive(:due_operations).and_wrap_original do |due_operations|
            snapshot = due_operations.call
            BillingOperation.find(operation.id).update!(state_update)
            snapshot
          end
          service
        end
      end

      context "when another worker processes it" do
        let(:state_update) { {processed_at: timestamp} }

        it "does not create an invoice or a successor" do
          expect(result).to be_success
          expect(operation.reload).to have_attributes(processed_at: timestamp, invoice_id: nil)
          expect(Invoice.where(customer:)).to be_empty
          expect(contract_rate_card.billing_operations.count).to eq(1)
        end
      end

      context "when another worker reschedules it" do
        let(:state_update) { {billing_at: timestamp + 1.day} }

        it "does not create an invoice or a successor" do
          expect(result).to be_success
          expect(operation.reload).to have_attributes(processed_at: nil, invoice_id: nil,
            billing_at: timestamp + 1.day)
          expect(Invoice.where(customer:)).to be_empty
          expect(contract_rate_card.billing_operations.count).to eq(1)
        end
      end
    end

    context "when termination cancels an operation after the due snapshot" do
      let(:action_type) { "close_fixed_arrears" }

      before do
        operation
        allow(described_class).to receive(:new).and_wrap_original do |original, *args, **kwargs|
          service = original.call(*args, **kwargs)
          allow(service).to receive(:due_operations).and_wrap_original do |due_operations|
            snapshot = due_operations.call
            BillingOperation.find(operation.id).update!(
              cancelled_at: timestamp,
              cancelled_causation_type: "contract_termination"
            )
            snapshot
          end
          service
        end
      end

      it "rechecks cancellation after acquiring the row lock" do
        expect(result).to be_success
        expect(operation.reload).to have_attributes(processed_at: nil, invoice_id: nil, cancelled_at: timestamp)
        expect(Invoice.where(customer:)).to be_empty
        expect(contract_rate_card.billing_operations.count).to eq(1)
      end
    end

    context "when contract billing settings change before the customer lock is acquired" do
      let(:timestamp) { Time.utc(2026, 3, 1) }
      let(:customer) { create(:customer, organization:, timezone: "UTC") }
      let(:contract) do
        create(:contract, organization:, customer:, started_at: Time.utc(2026, 2, 1),
          consolidate_invoice: true, purchase_order_number: "shared")
      end
      let(:second_contract) do
        create(:contract, organization:, customer:, started_at: Time.utc(2026, 2, 1),
          consolidate_invoice: true, purchase_order_number: "shared")
      end
      let(:product) { create(:product, :fixed, organization:) }
      let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
      let(:rate_card_rate) do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1),
          rate_model: "standard", rate_properties: {"amount" => "10"})
      end
      let(:contract_rate_card) do
        create(:contract_rate_card, organization:, contract:, rate_card:,
          effective_date: Date.new(2026, 2, 1), billing_anchor_date: Date.new(2026, 2, 1))
      end
      let(:second_contract_rate_card) do
        create(:contract_rate_card, organization:, contract: second_contract, rate_card:,
          effective_date: Date.new(2026, 2, 1), billing_anchor_date: Date.new(2026, 2, 1))
      end
      let(:first_schedule) { BillingOperations::BuildScheduleService.call!(contract_rate_card:).schedule }
      let(:second_schedule) { BillingOperations::BuildScheduleService.call!(contract_rate_card: second_contract_rate_card).schedule }
      let(:first_resolution) do
        BillingOperations::ResolvePlannedOperationService.call!(
          operation: BillingOperation.new(contract_rate_card:, action_type: "close_fixed_arrears",
            billing_at: timestamp, target_cycle_started_at: Time.utc(2026, 2, 1)),
          schedule: first_schedule
        )
      end
      let(:second_resolution) do
        BillingOperations::ResolvePlannedOperationService.call!(
          operation: BillingOperation.new(contract_rate_card: second_contract_rate_card,
            action_type: "close_fixed_arrears", billing_at: timestamp,
            target_cycle_started_at: Time.utc(2026, 2, 1)),
          schedule: second_schedule
        )
      end
      let(:operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: "close_fixed_arrears",
          billing_at: first_resolution.planned_operation.billing_at,
          target_cycle_started_at: first_resolution.planned_operation.cycle_started_at)
      end
      let(:second_operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card: second_contract_rate_card,
          action_type: "close_fixed_arrears",
          billing_at: second_resolution.planned_operation.billing_at,
          target_cycle_started_at: second_resolution.planned_operation.cycle_started_at)
      end

      before do
        rate_card_rate
        operation
        second_operation
        update_before_lock = true
        allow(Customers::LockService).to receive(:call!).and_wrap_original do |original, **kwargs, &block|
          if update_before_lock && kwargs[:scope] == :billing_schedule
            update_before_lock = false
            Contracts::UpdateService.call!(contract: second_contract, params: {purchase_order_number: "updated"})
          end

          original.call(**kwargs, &block)
        end
      end

      it "groups operations using the billing settings protected by the customer lock" do
        invoices = result.invoices

        expect(invoices.sort_by(&:purchase_order_number).map do |invoice|
          [invoice.purchase_order_number, invoice.fees.map(&:contract_id).uniq]
        end).to eq([["shared", [contract.id]], ["updated", [second_contract.id]]])
        expect(invoices).to all(be_finalized)
      end
    end

    context "when a renewal cycle starts after the contract ends" do
      let(:contract) do
        create(:contract, organization:, customer:, started_at: timestamp.beginning_of_month - 1.month,
          ended_at: timestamp.beginning_of_month)
      end
      let(:operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card:,
          action_type: "renew_fixed_advance", billing_at: timestamp - 1.day,
          target_cycle_started_at: timestamp.beginning_of_month)
      end

      it "leaves the obsolete operation pending without creating an invoice or successor" do
        operation

        expect(result).to be_success
        expect(operation.reload.processed_at).to be_nil
        expect(Invoice.where(customer:)).to be_empty
        expect(contract_rate_card.billing_operations.count).to eq(1)
      end
    end

    # Persisted adopted-segment states are obsolete; legacy conversion belongs to the bootstrap path.

    context "with two advance price slices in one nominal cycle" do
      let(:timestamp) { Time.utc(2026, 2, 1) }
      let(:customer) { create(:customer, organization:, timezone: "UTC") }
      let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 2, 1)) }
      let(:product) { create(:product, :fixed, organization:) }
      let(:rate_card) do
        create(:rate_card, :advance, organization:, product:, currency: "USD", proration: true)
      end
      let(:contract_rate_card) do
        create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: Date.new(2026, 2, 1), billing_anchor_date: Date.new(2026, 2, 1), units: 1)
      end
      let(:rate_card_rate) do
        create(:rate_card_rate, organization:, rate_card:, code: "before-midcycle", effective_from: Time.utc(2026, 1, 1), rate_model: "standard", rate_properties: {"amount" => "28"})
      end
      let(:later_rate) do
        create(:rate_card_rate, organization:, rate_card:, code: "after-midcycle", effective_from: Time.utc(2026, 2, 15), rate_model: "standard", rate_properties: {"amount" => "56"})
      end
      let(:schedule) do
        BillingOperations::BuildScheduleService.call!(
          contract_rate_card:
        ).schedule
      end
      let(:first_resolution) do
        BillingOperations::ResolvePlannedOperationService.call!(
          operation: BillingOperation.new(contract_rate_card:,
            action_type: "renew_fixed_advance", billing_at: timestamp,
            target_cycle_started_at: timestamp), schedule:
        )
      end
      let(:operation) do
        create(
          :billing_operation,
          organization:,
          customer:,
          contract_rate_card:,
          action_type: "renew_fixed_advance",
          billing_at: first_resolution.planned_operation.billing_at,
          target_cycle_started_at: first_resolution.planned_operation.cycle_started_at
        )
      end

      it "bills each due slice and chains the next operation in the same cycle" do
        rate_card_rate
        later_rate
        operation

        first = described_class.call!(customer:, timestamp: Time.utc(2026, 2, 1)).invoices.sole
        expect(first.fees.sum(:amount_cents)).to eq(1_400) # 2,800 × 14/28 for the first slice.
        expect(first.issuing_date.to_date).to eq(Date.new(2026, 2, 1))
        expect(first).to be_finalized
        expect(operation.reload.processed_at).to eq(Time.utc(2026, 2, 1))
        expect(operation.invoice_id).to eq(first.id)

        next_operation = contract_rate_card.billing_operations.pending.sole
        expect(next_operation).to have_attributes(
          billing_at: Time.utc(2026, 2, 15),
          target_cycle_started_at: Time.utc(2026, 2, 1)
        )
        expect(described_class.call!(customer:, timestamp: Time.utc(2026, 2, 14)).invoices).to be_empty

        second = described_class.call!(customer:, timestamp: Time.utc(2026, 2, 15)).invoices.sole
        expect(second.fees.sum(:amount_cents)).to eq(2_800) # 5,600 × 14/28 for the second slice.
        expect(second.issuing_date.to_date).to eq(Date.new(2026, 2, 15))
        expect(second).to be_finalized
        expect(contract_rate_card.billing_operations.pending.sole).to have_attributes(
          billing_at: Time.utc(2026, 3, 1), target_cycle_started_at: Time.utc(2026, 3, 1)
        )

        third = described_class.call!(customer:, timestamp: Time.utc(2026, 3, 1)).invoices.sole
        expect(third.fees.sum(:amount_cents)).to eq(5_600)
        expect(third.issuing_date.to_date).to eq(Date.new(2026, 3, 1))
        expect(third).to be_finalized
        expect(contract_rate_card.billing_operations.pending.order(:billing_at).last.target_cycle_started_at)
          .to eq(Time.utc(2026, 4, 1))
      end

      it "processes the initial snapshot once and defers due successors to the next call" do
        rate_card_rate
        later_rate
        operation
        queries = []
        subscriber = ->(*, payload) { queries << payload[:sql] }

        first_call = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
          described_class.call!(customer:, timestamp: Time.utc(2026, 3, 1))
        end

        expect(first_call.invoices.map { [it.issuing_date.to_date, it.fees.sum(:amount_cents)] }).to eq([
          [Date.new(2026, 2, 1), 1_400] # 2,800 × 14/28 for the first slice.
        ])
        expect(queries.count do |sql|
          sql.include?('FROM "billing_operations"') &&
            sql.include?("customer_id") && sql.include?("billing_at") &&
            sql.include?("processed_at") && !sql.include?("FOR UPDATE")
        end).to eq(1)
        expect(contract_rate_card.billing_operations.pending.sole).to have_attributes(
          billing_at: Time.utc(2026, 2, 15), target_cycle_started_at: Time.utc(2026, 2, 1)
        )

        second_call = described_class.call!(customer:, timestamp: Time.utc(2026, 3, 1))
        expect(second_call.invoices.map { [it.issuing_date.to_date, it.fees.sum(:amount_cents)] }).to eq([
          [Date.new(2026, 2, 15), 2_800] # 5,600 × 14/28 for the second slice.
        ])
        expect(contract_rate_card.billing_operations.where(processed_at: nil).sole.billing_at).to eq(Time.utc(2026, 3, 1))
      end

      it "commits no-output completion and continuation without an empty segment or invoice" do
        rate_card_rate
        later_rate
        operation
        allow(BillingOperations::ComputeInvoiceService).to receive(:call!) do |billing_segments:, **|
          outputs = billing_segments.index_with { [] }
          double(outputs:)
        end

        processed = described_class.call!(customer:, timestamp: Time.utc(2026, 3, 1))

        expect(processed.invoices).to be_empty
        expect(operation.reload.processed_at).to eq(Time.utc(2026, 3, 1))
        expect(operation.invoice_id).to be_nil
        expect(Invoice.where(customer:)).to be_empty
        expect(contract_rate_card.billing_operations.pending.sole).to have_attributes(
          billing_at: Time.utc(2026, 2, 15), target_cycle_started_at: Time.utc(2026, 2, 1)
        )
        expect(contract_rate_card.billing_operations.count).to eq(2)
      end

      it "finalizes generating invoices only after operation completion commits", transaction: false do
        rate_card_rate
        later_rate
        operation
        transaction_depth = ActiveRecord::Base.connection.open_transactions
        allow(Invoices::FinalizeContractInvoiceService).to receive(:call!) do |invoice:|
          expect(ActiveRecord::Base.connection.open_transactions).to eq(transaction_depth)
          expect(operation.reload.processed_at).to eq(Time.utc(2026, 2, 1))
          expect(contract_rate_card.billing_operations.where(billing_at: ..Time.utc(2026, 2, 1)).pluck(:processed_at))
            .to all(be_present)
          expect(invoice.reload).to be_generating
        end

        result = described_class.call!(customer:, timestamp: Time.utc(2026, 2, 1))

        expect(result.invoices.sole).to be_generating
        expect(Invoices::FinalizeContractInvoiceService).to have_received(:call!).once
      end

      it "rolls back output and completion when successor persistence fails" do
        rate_card_rate
        later_rate
        operation
        allow(BillingOperations::EnsureNextService).to receive(:call!).and_raise("successor failed")
        allow(Invoices::FinalizeContractInvoiceService).to receive(:call!)

        expect do
          described_class.call!(customer:, timestamp: Time.utc(2026, 2, 1))
        end.to raise_error(RuntimeError, "successor failed")
        expect(operation.reload.processed_at).to be_nil
        expect(operation.invoice_id).to be_nil
        expect(Invoice.where(customer:)).to be_empty
        expect(Fee.where(contract_rate_card:)).to be_empty
        expect(Invoices::FinalizeContractInvoiceService).not_to have_received(:call!)
      end
    end

    context "with two arrears price slices in one nominal cycle" do
      let(:timestamp) { Time.utc(2026, 2, 1) }
      let(:customer) { create(:customer, organization:, timezone: "UTC") }
      let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 2, 1)) }
      let(:product) { create(:product, :fixed, organization:) }
      let(:rate_card) do
        create(:rate_card, organization:, product:, currency: "USD", proration: true)
      end
      let(:contract_rate_card) do
        create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: Date.new(2026, 2, 1), billing_anchor_date: Date.new(2026, 2, 1), units: 1)
      end
      let(:rate_card_rate) do
        create(:rate_card_rate, organization:, rate_card:, code: "before-midcycle", effective_from: Time.utc(2026, 1, 1), rate_model: "standard", rate_properties: {"amount" => "28"})
      end
      let(:later_rate) do
        create(:rate_card_rate, organization:, rate_card:, code: "after-midcycle", effective_from: Time.utc(2026, 2, 15), rate_model: "standard", rate_properties: {"amount" => "56"})
      end
      let(:schedule) do
        BillingOperations::BuildScheduleService.call!(
          contract_rate_card:
        ).schedule
      end
      let(:first_planned_operation) do
        schedule.planned_operations_for_cycle(schedule.cycle_at(timestamp), action_type: "close_fixed_arrears").first
      end

      let(:operation) do
        create(
          :billing_operation,
          organization:,
          customer:,
          contract_rate_card:,
          action_type: "close_fixed_arrears",
          billing_at: first_planned_operation.billing_at,
          target_cycle_started_at: first_planned_operation.cycle_started_at
        )
      end

      context "when verifying resolution reuse" do
        before do
          rate_card_rate
          later_rate
          operation
          allow(BillingOperations::BuildScheduleService).to receive(:call!).and_call_original
          allow(BillingOperations::ResolvePlannedOperationService).to receive(:call!).and_call_original
        end

        it "resolves once and creates a successor with the correct cycle dates" do
          invoice = described_class.call!(customer:, timestamp: Time.utc(2026, 2, 15)).invoices.sole

          expect(invoice.fees.sum(:amount_cents)).to eq(1_400) # 2,800 × 14/28 for the first price slice.
          expect(operation.reload).to have_attributes(processed_at: Time.utc(2026, 2, 15), invoice_id: invoice.id)
          expect(contract_rate_card.billing_operations.pending.sole).to have_attributes(
            billing_at: Time.utc(2026, 3, 1),
            target_cycle_started_at: Time.utc(2026, 2, 1)
          )
          expect(BillingOperations::BuildScheduleService).to have_received(:call!).once
          expect(BillingOperations::ResolvePlannedOperationService).to have_received(:call!).once
        end
      end

      it "bills each arrears slice on its own date and chains within the cycle" do
        rate_card_rate
        later_rate
        operation

        expect(described_class.call!(customer:, timestamp: Time.utc(2026, 2, 14)).invoices).to be_empty
        expect(operation.reload.processed_at).to be_nil

        first = described_class.call!(customer:, timestamp: Time.utc(2026, 2, 15)).invoices.sole
        expect(first.fees.sum(:amount_cents)).to eq(1_400) # 2,800 × 14/28 for the first price slice.
        expect(first.issuing_date.to_date).to eq(Date.new(2026, 2, 15))
        expect(operation.reload.processed_at).to eq(Time.utc(2026, 2, 15))

        next_operation = contract_rate_card.billing_operations.pending.sole
        expect(next_operation).to have_attributes(
          billing_at: Time.utc(2026, 3, 1),
          target_cycle_started_at: Time.utc(2026, 2, 1)
        )

        second = described_class.call!(customer:, timestamp: Time.utc(2026, 3, 1)).invoices.sole
        expect(second.fees.sum(:amount_cents)).to eq(2_800) # 5,600 × 14/28 for the second price slice.
        expect(second.issuing_date.to_date).to eq(Date.new(2026, 3, 1))
        expect(contract_rate_card.billing_operations.pending.sole).to have_attributes(
          billing_at: Time.utc(2026, 4, 1), target_cycle_started_at: Time.utc(2026, 3, 1)
        )
      end
    end

    context "with a recurring metered advance renewal with no event output" do
      let(:timestamp) { Time.utc(2026, 2, 1) }
      let(:customer) { create(:customer, organization:, timezone: "UTC") }
      let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 2, 1)) }
      let(:metric) { create(:sum_billable_metric, organization:, field_name: "quantity", recurring: true) }
      let(:product) { create(:product, :metered, organization:, billable_metric: metric) }
      let(:rate_card) do
        create(:rate_card, :advance, organization:, product:, currency: "USD", display_on_invoice: true)
      end
      let(:contract_rate_card) do
        create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: Date.new(2026, 2, 1), billing_anchor_date: Date.new(2026, 2, 1))
      end
      let(:rate) do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1), rate_model: "standard", rate_properties: {"amount" => "10"})
      end
      let(:schedule) do
        BillingOperations::BuildScheduleService.call!(
          contract_rate_card:
        ).schedule
      end
      let(:resolution) do
        BillingOperations::ResolvePlannedOperationService.call!(
          operation: BillingOperation.new(contract_rate_card:,
            action_type: "renew_recurring_metered_advance", billing_at: timestamp,
            target_cycle_started_at: timestamp), schedule:
        )
      end
      let(:operation) do
        create(
          :billing_operation,
          organization:,
          customer:,
          contract_rate_card:,
          action_type: "renew_recurring_metered_advance",
          billing_at: resolution.planned_operation.billing_at,
          target_cycle_started_at: resolution.planned_operation.cycle_started_at
        )
      end

      it "resolves no usage without an empty segment or invoice and continues the chain" do
        rate
        operation

        outcome = described_class.call!(customer:, timestamp: Time.utc(2026, 2, 1))

        expect(outcome.invoices).to be_empty
        expect(operation.reload.processed_at).to eq(Time.utc(2026, 2, 1))
        expect(operation.invoice_id).to be_nil
        expect(Invoice.where(customer:)).to be_empty
        expect(contract_rate_card.billing_operations.pending.sole.target_cycle_started_at).to eq(Time.utc(2026, 3, 1))
      end

      it "bills recurring usage from history without creating future segments" do
        rate
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: metric.code, timestamp: Time.utc(2026, 1, 20), properties: {quantity: 1})
        operation

        invoice = described_class.call!(customer:, timestamp: Time.utc(2026, 2, 1)).invoices.sole

        expect(invoice.fees.sole).to have_attributes(units: 1, amount_cents: 1_000)
        expect(operation.reload.processed_at).to eq(Time.utc(2026, 2, 1))
        expect(operation.reload.invoice_id).to eq(invoice.id)
        expect(LegacyBillingSegment.where(contract_rate_card_id: contract_rate_card.id).count).to eq(0)
        expect(contract_rate_card.billing_operations.pending.sole.target_cycle_started_at).to eq(Time.utc(2026, 3, 1))
      end
    end

    context "with metered arrears usage" do
      let(:timestamp) { Time.utc(2026, 2, 1) }
      let(:customer) { create(:customer, organization:, timezone: "UTC") }
      let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 2, 1)) }
      let(:metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
      let(:product) { create(:product, :metered, organization:, billable_metric: metric) }
      let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
      let(:contract_rate_card) do
        create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: Date.new(2026, 2, 1), billing_anchor_date: Date.new(2026, 2, 1))
      end
      let(:rate) do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1), rate_model: "standard", rate_properties: {"amount" => "10"})
      end
      let(:schedule) do
        BillingOperations::BuildScheduleService.call!(
          contract_rate_card:
        ).schedule
      end
      let(:planned_operation) do
        schedule.planned_operations_for_cycle(schedule.cycle_at(timestamp), action_type: "close_metered_arrears").first
      end
      let(:operation) do
        create(
          :billing_operation,
          organization:,
          customer:,
          contract_rate_card:,
          action_type: "close_metered_arrears",
          billing_at: planned_operation.billing_at,
          target_cycle_started_at: planned_operation.cycle_started_at
        )
      end

      it "bills usage once at period close and links the invoice to the operation" do
        rate
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: metric.code, timestamp: Time.utc(2026, 2, 10), properties: {})
        operation

        invoice = described_class.call!(customer:, timestamp: Time.utc(2026, 3, 1)).invoices.sole

        expect(invoice.fees.sole).to have_attributes(units: 1, amount_cents: 1_000)
        expect(invoice.issuing_date.to_date).to eq(Date.new(2026, 3, 1))
        expect(operation.reload.processed_at).to eq(Time.utc(2026, 3, 1))
        expect(operation.reload.invoice_id).to eq(invoice.id)
      end
    end

    context "with paid advance fees to regroup" do
      let(:timestamp) { Time.utc(2026, 2, 1) }
      let(:customer) { create(:customer, organization:, timezone: "UTC") }
      let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 2, 1)) }
      let(:metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
      let(:product) { create(:product, :metered, organization:, billable_metric: metric) }
      let(:rate_card) do
        create(:rate_card, :advance, organization:, product:, currency: "USD", display_on_invoice: false, regroup_paid_fees: :invoice)
      end
      let(:contract_rate_card) do
        create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: Date.new(2026, 2, 1), billing_anchor_date: Date.new(2026, 2, 1))
      end
      let(:rate) do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1), rate_model: "standard", rate_properties: {"amount" => "10"})
      end
      let(:schedule) do
        BillingOperations::BuildScheduleService.call!(
          contract_rate_card:
        ).schedule
      end
      let(:resolution) do
        BillingOperations::ResolvePlannedOperationService.call!(
          operation: BillingOperation.new(contract_rate_card:,
            action_type: "regroup_paid_fees", billing_at: Time.utc(2026, 3, 1),
            target_cycle_started_at: timestamp), schedule:
        )
      end
      let(:operation) do
        create(
          :billing_operation,
          organization:,
          customer:,
          contract_rate_card:,
          action_type: "regroup_paid_fees",
          causation_type: :late_payment,
          billing_at: resolution.planned_operation.billing_at,
          target_cycle_started_at: resolution.planned_operation.cycle_started_at
        )
      end
      let(:source_segment) do
        BillingSegments::BuildEventSegmentService.call!(
          contract_rate_card:, billable_segment: resolution.planned_operation.billable_segments.sole
        ).billing_segment
      end
      let(:paid_fee) do
        metered_item = Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: source_segment)
        create(
          :fee,
          :succeeded,
          invoice: nil,
          subscription: nil,
          organization:,
          billing_entity: customer.billing_entity,
          contract:,
          contract_rate_card:,
          rate_card_rate: rate,
          invoiceable: product,
          fee_type: :product,
          amount_currency: "USD",
          amount_cents: 500,
          taxes_amount_cents: 100,
          pay_in_advance: true,
          succeeded_at: Time.utc(2026, 2, 10),
          properties: metered_item.filtered_for_charge_boundaries
        )
      end

      it "attaches the original paid fee once and records the service-end date" do
        rate
        operation
        original_fee = paid_fee

        invoice = described_class.call!(customer:, timestamp: Time.utc(2026, 3, 1)).invoices.sole

        expect(invoice.fees).to contain_exactly(original_fee)
        expect(invoice.issuing_date.to_date).to eq(Date.new(2026, 3, 1))
        expect(original_fee.reload.invoice_id).to eq(invoice.id)
        expect(operation.reload.invoice_id).to eq(invoice.id)
        invoice_count = Invoice.count
        fee_count = Fee.count
        expect(described_class.call!(customer:, timestamp: Time.utc(2026, 3, 1)).invoices).to be_empty
        expect(Invoice.count).to eq(invoice_count)
        expect(Fee.count).to eq(fee_count)
        expect(original_fee.reload.invoice_id).to eq(invoice.id)
      end

      context "when successor persistence fails" do
        let(:original_fee) { paid_fee }

        before do
          rate
          operation
          original_fee
          allow(BillingOperations::EnsureNextService).to receive(:call!).and_raise("successor failed")
        end

        it "rolls back regroup output and completion" do
          expect do
            described_class.call!(customer:, timestamp: Time.utc(2026, 3, 1))
          end.to raise_error(RuntimeError, "successor failed")

          expect(original_fee.reload.invoice_id).to be_nil
          expect(operation.reload).to have_attributes(processed_at: nil, invoice_id: nil)
          expect(Invoice.where(customer:)).to be_empty
        end
      end

      context "with a regroup operation whose card configuration has changed" do
        let(:contract) { create(:contract, organization:, customer:, consolidate_invoice: true) }
        let(:reconfigured_metric) { create(:billable_metric, organization:) }
        let(:reconfigured_product) { create(:product, :metered, organization:, billable_metric: reconfigured_metric) }
        let(:reconfigured_rate_card) do
          create(:rate_card, :advance, organization:, product: reconfigured_product, currency: "USD", display_on_invoice: false)
        end
        let(:reconfigured_contract_rate_card) do
          create(:contract_rate_card, organization:, contract:, rate_card: reconfigured_rate_card,
            effective_date: Date.new(2026, 2, 1), billing_anchor_date: Date.new(2026, 2, 1))
        end
        let(:reconfigured_operation) do
          create(:billing_operation, organization:, customer:,
            contract_rate_card: reconfigured_contract_rate_card, action_type: "regroup_paid_fees",
            causation_type: :periodic_continuation, billing_at: operation.billing_at,
            target_cycle_started_at: operation.target_cycle_started_at)
        end
        let(:invoice) { described_class.call!(customer:, timestamp: Time.utc(2026, 3, 1)).invoices.sole }

        before do
          rate
          operation
          create(:rate_card_rate, organization:, rate_card: reconfigured_rate_card,
            effective_from: Time.utc(2026, 1, 1), rate_model: "standard", rate_properties: {"amount" => "10"})
          reconfigured_operation
          paid_fee
        end

        it "completes the stored action and creates its successor without attributing unrelated output" do
          expect(invoice.fees).to contain_exactly(paid_fee)
          expect(reconfigured_operation.reload).to have_attributes(processed_at: Time.utc(2026, 3, 1), invoice_id: nil)
          expect(reconfigured_contract_rate_card.billing_operations.count).to eq(2)
          expect(reconfigured_contract_rate_card.billing_operations.order(:billing_at).last)
            .to have_attributes(action_type: "regroup_paid_fees", billing_at: Time.utc(2026, 4, 1))
        end
      end

      context "with another eligible regroup operation that has no paid output" do
        let(:contract) { create(:contract, organization:, customer:, consolidate_invoice: true) }
        let(:empty_metric) { create(:billable_metric, organization:) }
        let(:empty_product) { create(:product, :metered, organization:, billable_metric: empty_metric) }
        let(:empty_rate_card) do
          create(:rate_card, :advance, organization:, product: empty_product, currency: "USD",
            display_on_invoice: false, regroup_paid_fees: :invoice)
        end
        let(:empty_contract_rate_card) do
          create(:contract_rate_card, organization:, contract:, rate_card: empty_rate_card,
            effective_date: Date.new(2026, 2, 1), billing_anchor_date: Date.new(2026, 2, 1))
        end
        let(:empty_schedule) do
          BillingOperations::BuildScheduleService.call!(
            contract_rate_card: empty_contract_rate_card
          ).schedule
        end
        let(:empty_resolution) do
          BillingOperations::ResolvePlannedOperationService.call!(
            operation: BillingOperation.new(contract_rate_card: empty_contract_rate_card,
              action_type: "regroup_paid_fees", billing_at: Time.utc(2026, 3, 1),
              target_cycle_started_at: timestamp), schedule: empty_schedule
          )
        end
        let(:empty_operation) do
          create(:billing_operation, organization:, customer:,
            contract_rate_card: empty_contract_rate_card, action_type: "regroup_paid_fees",
            causation_type: :late_payment, billing_at: empty_resolution.planned_operation.billing_at,
            target_cycle_started_at: empty_resolution.planned_operation.cycle_started_at)
        end
        let(:invoice) { described_class.call!(customer:, timestamp: Time.utc(2026, 3, 1)).invoices.sole }

        before do
          rate
          create(:rate_card_rate, organization:, rate_card: empty_rate_card,
            effective_from: Time.utc(2026, 1, 1), rate_model: "standard", rate_properties: {"amount" => "10"})
          operation
          empty_operation
          paid_fee
        end

        it "links only the operation whose segment produced paid output and completes both" do
          expect(invoice.fees).to contain_exactly(paid_fee)
          expect(operation.reload).to have_attributes(processed_at: Time.utc(2026, 3, 1), invoice_id: invoice.id)
          expect(empty_operation.reload).to have_attributes(processed_at: Time.utc(2026, 3, 1), invoice_id: nil)
          expect(contract_rate_card.billing_operations.count).to eq(1)
          expect(empty_contract_rate_card.billing_operations.count).to eq(1)
        end
      end
    end
  end
end
