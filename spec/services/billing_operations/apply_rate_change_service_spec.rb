# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ApplyRateChangeService do
  subject(:result) { described_class.call(customer:, rate_card_rate_id: rate.id) }

  let(:organization) { create(:organization, feature_flags: []) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:billing_timing) { "arrears" }
  let(:billing_scope) { "segment" }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, currency: "USD") }
  let(:effective_from) { Time.utc(2026, 11, 15) }
  let(:old_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 1)) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from:) }
  let(:clock) { Time.utc(2026, 12, 1) }
  let(:card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:,
      effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1),
      units: 1, next_billing_at: clock || Time.utc(2026, 12, 1))
  end

  around { |example| travel_to(Time.utc(2026, 11, 12)) { example.run } }

  before do
    card
    card.update!(next_billing_at: nil) if clock.nil?
    old_rate
    rate
  end

  it "wakes the clock at the rate boundary without creating operations or enqueuing processing" do
    expect { result }.not_to change(BillingOperation, :count)
    expect(result).to be_success
    expect(card.reload.next_billing_at).to eq(effective_from)
    expect(BillingOperations::ProcessJob).not_to have_been_enqueued
  end

  context "with cycle scope" do
    let(:billing_scope) { "cycle" }

    it "keeps the natural cycle close" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
      expect(BillingOperation.where(contract_rate_card: card)).to be_empty
    end

    context "when a historical rate is inserted after the cycle was closed" do
      let(:old_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: contract.started_at, rate_properties: {"amount" => "30"}) }
      let(:closed_invoice) do
        travel_to(Time.utc(2026, 12, 1))
        BillingOperations::ScheduleService.call!(customer:, timestamp: Time.current)
        invoice = BillingOperations::ProcessService.call!(customer:, timestamp: Time.current).invoices.sole
        travel_to(Time.utc(2026, 12, 5))
        invoice
      end
      # Legacy/imported rows can bypass the API's rejection of backdated rates.
      let(:rate) do
        closed_invoice
        super()
      end

      it "keeps the completed invoice and operation unchanged and continues with the next cycle" do
        invoice_attributes = closed_invoice.attributes
        fee_attributes = closed_invoice.fees.order(:id).map(&:attributes)
        completed_operation = closed_invoice.billing_operations.sole
        operation_attributes = completed_operation.attributes
        expect(closed_invoice.total_amount_cents).to eq(3000) # $30 for the full November cycle before the historical rate existed.

        expect { result }.not_to change(BillingOperation, :count)
        expect(result).to be_success
        expect(closed_invoice.reload.attributes).to eq(invoice_attributes)
        expect(closed_invoice.fees.order(:id).map(&:attributes)).to eq(fee_attributes)
        expect(completed_operation.reload.attributes).to eq(operation_attributes)
        expect(card.reload.next_billing_at).to eq(Time.utc(2027, 1, 1))
        expect(BillingOperations::ScheduleService.call!(customer:, timestamp: Time.current).billing_operations).to be_empty
        expect(BillingOperations::ProcessService.call!(customer:, timestamp: Time.current).invoices).to be_empty
        expect(customer.invoices.pluck(:id)).to eq([closed_invoice.id])
      end
    end
  end

  context "with fixed advance" do
    let(:billing_timing) { "advance" }
    let(:reconciliations) { card.billing_operations.where(action_type: "reconcile_advance_coverage") }

    it "replans without reconciling when nothing has been billed" do
      expect { result }.not_to change(BillingOperation, :count)
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 11, 1))
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
    end

    def record_coverage(card, ended_at:, processed_at:)
      operation = create(:billing_operation, organization:, customer:, contract_rate_card: card, action_type: "renew_fixed_advance",
        billing_at: contract.started_at, target_cycle_started_at: contract.started_at,
        coverage_started_at: contract.started_at, coverage_ended_at: ended_at, processed_at:)
      operation.segments.create!(organization:, position: 0, rate_card_rate: old_rate, started_at: contract.started_at,
        ended_at:, proration_ratio: 1)
    end

    context "when the latest completed operation has no saved segments" do
      let(:completed_operation) do
        create(:billing_operation, organization:, customer:, contract_rate_card: card, billing_at: Time.current,
          processed_at: Time.current, target_cycle_started_at: contract.started_at, coverage_started_at: Time.current, coverage_ended_at: clock)
      end

      before do
        record_coverage(card, ended_at: clock, processed_at: contract.started_at)
        completed_operation
      end

      it "snapshots the whole target cycle without filling in the missing source segments" do
        expect { result }.to change(reconciliations, :count).by(1)
        expect(result).to be_success
        reconciliation = reconciliations.sole
        expect(reconciliation.target_cycle_started_at).to eq(completed_operation.target_cycle_started_at)
        expect(reconciliation.segments.pluck(:started_at, :ended_at, :rate_card_rate_id)).to eq([
          [contract.started_at, effective_from, old_rate.id],
          [effective_from, clock, rate.id]
        ])
        expect(completed_operation.reload.segments).to be_empty
      end
    end

    context "when November was already billed" do
      let(:processed_at) { Time.utc(2026, 11, 1) }

      before { record_coverage(card, ended_at: Time.utc(2026, 12, 1), processed_at:) }

      context "with two rate changes in the same cycle" do
        let(:billing_scope) { "cycle" }
        let(:later_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 20)) }

        it "saves a separate schedule snapshot for each change" do
          expect(result).to be_success
          first = reconciliations.sole
          described_class.call!(customer:, rate_card_rate_id: later_rate.id)
          second = reconciliations.where.not(id: first.id).sole
          expect(first.segments.pluck(:rate_card_rate_id)).to eq([old_rate.id, rate.id])
          expect(second.segments.pluck(:rate_card_rate_id)).to eq([old_rate.id, rate.id, later_rate.id])
        end
      end

      context "with multiple affected cards" do
        let(:other_contract) { create(:contract, organization:, customer:, started_at: contract.started_at) }
        let(:other_card) {
          create(:contract_rate_card, organization:, contract: other_contract, rate_card:, billing_scope:,
            effective_date: card.effective_date, billing_anchor_date: card.billing_anchor_date, next_billing_at: clock)
        }

        before { record_coverage(other_card, ended_at: clock, processed_at:) }

        it "loads completed and pending periodic work in batches without reading saved segments" do
          queries = capture_sql { expect(result).to be_success }
          history_queries = queries.grep(/SELECT DISTINCT ON .*FROM "billing_operations"/)
          expect(history_queries.grep(/"processed_at" IS NOT NULL/).size).to eq(1)
          expect(history_queries.grep(/"processed_at" IS NULL/).size).to eq(1)
          expect(queries.grep(/SELECT .*FROM "billing_operation_segments"/)).to be_empty
          expect(customer.billing_operations.pending.pluck(:contract_rate_card_id)).to contain_exactly(card.id, other_card.id)
        end
      end

      it "queues the revised coverage once without moving the renewal or starting processing" do
        expect { result }.to change(reconciliations, :count).by(1)
        expect(result).to be_success
        reconciliation = reconciliations.sole
        expect(reconciliation).to have_attributes(
          reason: "rate_change", billing_at: contract.started_at, target_cycle_started_at: contract.started_at,
          coverage_started_at: contract.started_at, coverage_ended_at: clock, invoice_id: nil
        )
        expect(reconciliation.segments.pluck(:started_at, :ended_at, :rate_card_rate_id)).to eq([
          [contract.started_at, effective_from, old_rate.id],
          [effective_from, clock, rate.id]
        ])
        described_class.call!(customer:, rate_card_rate_id: rate.id)
        expect(reconciliations.pluck(:id)).to eq([reconciliation.id])
        expect(card.reload.next_billing_at).to eq(clock)
        expect(BillingOperations::ProcessJob).not_to have_been_enqueued
      end

      context "when the clock is already earlier" do
        let(:clock) { Time.utc(2026, 11, 10) }

        it "reconciles the purchased coverage and projects the next renewal from it" do
          expect { result }.to change(reconciliations, :count).by(1)
          expect(card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
        end
      end

      context "when the change starts at the coverage end" do
        let(:effective_from) { Time.utc(2026, 12, 1) }

        it "snapshots the unchanged target cycle and leaves the next cycle to periodic scheduling" do
          expect(result).to be_success
          reconciliation = reconciliations.sole
          expect(reconciliation.target_cycle_started_at).to eq(contract.started_at)
          expect(reconciliation.segments.pluck(:started_at, :ended_at, :rate_card_rate_id)).to eq([
            [contract.started_at, effective_from, old_rate.id]
          ])
          expect(card.reload.next_billing_at).to eq(effective_from)
        end

        context "when the revised schedule no longer covers the purchased start" do
          before { old_rate.discard! }

          it "does not substitute a future obligation" do
            expect(result).to be_success
            expect(reconciliations).to be_empty
            expect(card.reload.next_billing_at).to eq(effective_from)
          end
        end
      end

      context "when the renewal is still pending" do
        let(:processed_at) { nil }

        it "reconciles the pending renewal without changing its snapshot or wake date" do
          renewal = card.billing_operations.periodic.pending.sole
          renewal_attributes = renewal.attributes
          saved_segments = renewal.segments.map(&:attributes)

          expect { result }.to change(reconciliations, :count).by(1)
          expect(result).to be_success
          expect(reconciliations.sole.target_cycle_started_at).to eq(renewal.target_cycle_started_at)
          expect(renewal.reload.attributes).to eq(renewal_attributes)
          expect(renewal.segments.map(&:attributes)).to eq(saved_segments)
          expect(card.reload.next_billing_at).to eq(renewal.billing_at)
        end
      end

      context "when another price starts before the purchased coverage ends" do
        let(:later_start) { Time.utc(2026, 11, 20) }
        let(:later_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: later_start) }

        before { later_rate }

        it "reconciles all revised slices of the purchased coverage" do
          expect(result).to be_success
          reconciliation = reconciliations.sole
          expect(reconciliation).to have_attributes(coverage_started_at: contract.started_at, coverage_ended_at: clock)
          expect(reconciliation.segments.pluck(:started_at, :ended_at, :rate_card_rate_id)).to eq([
            [contract.started_at, effective_from, old_rate.id],
            [effective_from, later_start, rate.id],
            [later_start, clock, later_rate.id]
          ])
        end
      end
    end

    [15, 18].each do |day|
      context "when an intervening rate starts on November #{day}, before the changed rate" do
        let(:clock) { Time.utc(2026, 11, 15) }
        let(:intervening_start) { Time.utc(2026, 11, day) }
        let(:effective_from) { Time.utc(2026, 11, 20) }
        let(:intervening_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: intervening_start) }

        before do
          intervening_rate
          record_coverage(card, ended_at: clock, processed_at: contract.started_at)
        end

        it "projects the next periodic wake and snapshots all segments in the target cycle" do
          expect(result).to be_success
          expect(card.reload.next_billing_at).to eq(intervening_start)
          expect(card.billing_operations.periodic.pending).to be_empty
          expect(reconciliations.sole.segments.pluck(:started_at, :ended_at, :rate_card_rate_id)).to eq([
            [contract.started_at, intervening_start, old_rate.id],
            [intervening_start, effective_from, intervening_rate.id],
            [effective_from, Time.utc(2026, 12, 1), rate.id]
          ])
        end
      end
    end

    context "when a pending December renewal was saved before a rate was postponed" do
      let(:effective_from) { Time.utc(2026, 12, 15) }
      let(:revised_start) { Time.utc(2026, 12, 20) }
      let(:cycle_end) { Time.utc(2027, 1, 1) }
      let(:rate_card) { create(:rate_card, :advance, organization:, product:, currency: "USD", proration: true) }
      let(:card) do
        create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:,
          effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1),
          units: 1, next_billing_at: contract.started_at)
      end
      let(:old_rate) do
        create(:rate_card_rate, organization:, rate_card:, effective_from: contract.started_at, rate_properties: {"amount" => "31"})
      end
      let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from:, rate_properties: {"amount" => "62"}) }
      let(:renewal) { BillingOperations::ScheduleService.call!(customer:, timestamp: Time.current).billing_operations.sole }
      let(:november_invoice) do
        travel_to(contract.started_at)
        BillingOperations::ScheduleService.call!(customer:, timestamp: Time.current)
        BillingOperations::ProcessService.call!(customer:, timestamp: Time.current).invoices.sole
      end

      before do
        november_invoice
        travel_to(clock)
        renewal
      end

      shared_examples "reconciliation of a saved December renewal" do
        it "preserves and bills the saved renewal while snapshotting both target cycles once" do
          renewal_attributes = renewal.attributes
          saved_segments = renewal.segments.map(&:attributes)
          november_invoice_attributes = november_invoice.attributes

          RateCardRates::UpdateService.call!(rate_card_rate: rate, params: {effective_from: revised_start})
          expect { result }.to change(reconciliations, :count).by(2)
          expect(result).to be_success

          november_snapshot = reconciliations.where(target_cycle_started_at: contract.started_at).sole
          expect(november_snapshot).to have_attributes(coverage_started_at: contract.started_at, coverage_ended_at: clock)
          expect(november_snapshot.segments.pluck(:rate_card_rate_id, :started_at, :ended_at, :proration_ratio)).to eq([
            [old_rate.id, contract.started_at, clock, 1]
          ])
          november_renewal = november_invoice.billing_operations.sole
          expect(november_snapshot.segments.pluck(:rate_card_rate_id, :started_at, :ended_at, :proration_ratio))
            .to eq(november_renewal.segments.pluck(:rate_card_rate_id, :started_at, :ended_at, :proration_ratio))

          december_snapshot = reconciliations.where(target_cycle_started_at: clock).sole
          expect(december_snapshot).to have_attributes(
            reason: "rate_change", coverage_started_at: clock, coverage_ended_at: cycle_end
          )
          expect(december_snapshot.segments.pluck(:rate_card_rate_id, :started_at, :ended_at, :proration_ratio)).to eq([
            [old_rate.id, clock, revised_start, (BigDecimal("19") / 31).round(10)],
            [rate.id, revised_start, cycle_end, (BigDecimal("12") / 31).round(10)]
          ]) # December's 31 days split at the new rate's December 20 start.

          described_class.call!(customer:, rate_card_rate_id: rate.id)
          expect(reconciliations.pluck(:id)).to contain_exactly(november_snapshot.id, december_snapshot.id)
          expect(renewal.reload.attributes).to eq(renewal_attributes)
          expect(renewal.segments.map(&:attributes)).to eq(saved_segments)
          expect(BillingOperations::ProcessJob).not_to have_been_enqueued

          invoice = BillingOperations::ProcessService.call!(customer:, timestamp: Time.current).invoices.sole
          expect(invoice.billing_operations.pluck(:id)).to eq([renewal.id])
          expect(invoice.fees.order(:amount_cents).pluck(:amount_cents)).to eq(saved_fee_amounts)
          expect(invoice.total_amount_cents).to eq(saved_fee_amounts.sum)
          completed_attributes = renewal.reload.attributes

          described_class.call!(customer:, rate_card_rate_id: rate.id)
          expect(reconciliations.pluck(:id)).to contain_exactly(november_snapshot.id, december_snapshot.id)
          expect(reconciliations).to all(have_attributes(processed_at: nil, invoice_id: nil))
          expect(november_invoice.reload.attributes).to eq(november_invoice_attributes)
          expect(renewal.reload.attributes).to eq(completed_attributes)
          expect(renewal.segments.map(&:attributes)).to eq(saved_segments)
        end
      end

      context "with cycle scope" do
        let(:billing_scope) { "cycle" }
        let(:saved_fee_amounts) { [1400, 3400] } # $31 * 14/31 days, then $62 * 17/31 days.

        it_behaves_like "reconciliation of a saved December renewal"
      end

      context "with segment scope" do
        let(:saved_fee_amounts) { [1400] } # $31 * 14/31 days.

        it_behaves_like "reconciliation of a saved December renewal"

        it "bills the later rate only from its new start" do
          RateCardRates::UpdateService.call!(rate_card_rate: rate, params: {effective_from: revised_start})
          expect(result).to be_success
          BillingOperations::ProcessService.call!(customer:, timestamp: Time.current)

          travel_to(revised_start)
          later_renewal = BillingOperations::ScheduleService.call!(customer:, timestamp: Time.current).billing_operations.sole
          expect(later_renewal).to have_attributes(
            billing_at: revised_start, coverage_started_at: revised_start, coverage_ended_at: cycle_end
          )
          invoice = BillingOperations::ProcessService.call!(customer:, timestamp: Time.current).invoices.sole
          expect(invoice.billing_operations.pluck(:id)).to eq([later_renewal.id])
          expect(invoice.total_amount_cents).to eq(2400) # $62 * 12/31 days.
        end
      end
    end

    context "with queued fixed advance renewals in January" do
      let(:clock) { Time.utc(2027, 1, 1) }
      let(:next_cycle_start) { Time.utc(2027, 2, 1) }
      let(:march_start) { Time.utc(2027, 3, 1) }
      let(:contract) { create(:contract, organization:, customer:, started_at: clock) }
      let(:card) do
        create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:,
          effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1), units: 1, next_billing_at: clock)
      end
      let(:old_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: clock) }
      let(:rate) do
        renewals
        travel_to(change_at)
        new_rate
      end
      let(:new_rate) do
        RateCardRates::CreateService.call!(rate_card:, params: {
          code: "new-rate", effective_from: change_at, rate_model: "standard", billing_interval_unit: "month", rate_properties: {"amount" => "62"}
        }).rate_card_rate
      end

      context "when two cycles are pending and the edit affects only the second" do
        let(:billing_scope) { "cycle" }
        let(:change_at) { Time.utc(2027, 2, 15) }
        let(:renewals) do
          travel_to(next_cycle_start)
          BillingOperations::ScheduleService.call!(customer:, timestamp: Time.current).billing_operations
        end

        it "snapshots both target cycles and reuses them after the renewals complete" do
          expect(renewals.map(&:billing_at)).to eq([clock, next_cycle_start])
          expect { result }.to change(reconciliations, :count).by(2)
          expect(result).to be_success

          january_snapshot = reconciliations.where(target_cycle_started_at: clock).sole
          expect(january_snapshot).to have_attributes(coverage_started_at: clock, coverage_ended_at: next_cycle_start)
          expect(january_snapshot.segments.pluck(:started_at, :ended_at, :rate_card_rate_id)).to eq([
            [clock, next_cycle_start, old_rate.id]
          ])
          february_snapshot = reconciliations.where(target_cycle_started_at: next_cycle_start).sole
          expect(february_snapshot).to have_attributes(coverage_started_at: next_cycle_start, coverage_ended_at: march_start)
          expect(february_snapshot.segments.pluck(:started_at, :ended_at, :rate_card_rate_id)).to eq([
            [next_cycle_start, change_at, old_rate.id],
            [change_at, march_start, rate.id]
          ])

          renewals.each do |renewal|
            invoice = BillingOperations::ProcessService.call!(customer:, timestamp: Time.current).invoices.sole
            expect(invoice.billing_operations.pluck(:id)).to eq([renewal.id])
          end

          described_class.call!(customer:, rate_card_rate_id: rate.id)
          expect(reconciliations.pluck(:id)).to contain_exactly(january_snapshot.id, february_snapshot.id)
          expect(reconciliations).to all(have_attributes(processed_at: nil, invoice_id: nil))
        end
      end

      context "when two segments of the same cycle are pending" do
        let(:second_start) { Time.utc(2027, 1, 15) }
        let(:change_at) { second_start + 12.hours }
        let(:second_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: second_start) }
        let(:renewals) do
          travel_to(clock)
          second_rate
          first = BillingOperations::ScheduleService.call!(customer:, timestamp: Time.current).billing_operations
          travel_to(second_start)
          first + BillingOperations::ScheduleService.call!(customer:, timestamp: Time.current).billing_operations
        end

        it "records one snapshot containing all three slices of the target cycle" do
          expect(renewals.map(&:billing_at)).to eq([clock, second_start])
          expect(result).to be_success
          reconciliation = reconciliations.sole
          expect(reconciliation).to have_attributes(
            billing_at: clock, target_cycle_started_at: clock, coverage_started_at: clock, coverage_ended_at: next_cycle_start
          )
          expect(reconciliation.segments.pluck(:started_at, :ended_at, :rate_card_rate_id)).to eq([
            [clock, second_start, old_rate.id],
            [second_start, change_at, second_rate.id],
            [change_at, next_cycle_start, rate.id]
          ])
        end
      end

      context "when the rate change is delivered after two renewals have completed" do
        let(:billing_scope) { "cycle" }
        let(:change_at) { Time.utc(2027, 1, 15) }
        let(:january_renewal) { BillingOperations::ScheduleService.call!(customer:, timestamp: Time.current).billing_operations.sole }
        let(:february_renewal) { BillingOperations::ScheduleService.call!(customer:, timestamp: Time.current).billing_operations.sole }
        let(:rate) do
          travel_to(clock)
          january_renewal
          new_rate
        end
        let(:january_processed_at) { clock + 1.hour }

        before do
          travel_to(january_processed_at)
          BillingOperations::ProcessService.call!(customer:, timestamp: Time.current)
          travel_to(next_cycle_start)
          february_renewal
          BillingOperations::ProcessService.call!(customer:, timestamp: Time.current)
          travel_to(next_cycle_start + 1.day)
        end

        it "snapshots both January's changed coverage and February's unchanged coverage" do
          expect(january_renewal.reload.processed_at).to eq(january_processed_at)
          expect(january_renewal.invoice.fees.pluck(:rate_card_rate_id)).to eq([old_rate.id])
          expect(february_renewal.reload.processed_at).to eq(next_cycle_start)
          expect(february_renewal.invoice.fees.pluck(:rate_card_rate_id)).to eq([rate.id])

          expect { result }.to change(reconciliations, :count).by(2)
          expect(result).to be_success

          january_snapshot = reconciliations.where(target_cycle_started_at: january_renewal.target_cycle_started_at).sole
          expect(january_snapshot.segments.pluck(:started_at, :ended_at, :rate_card_rate_id)).to eq([
            [clock, change_at, old_rate.id],
            [change_at, next_cycle_start, rate.id]
          ])
          february_snapshot = reconciliations.where(target_cycle_started_at: february_renewal.target_cycle_started_at).sole
          expect(february_snapshot.segments.pluck(:started_at, :ended_at, :rate_card_rate_id)).to eq([
            [next_cycle_start, march_start, rate.id]
          ])
        end
      end

      context "when a future price is edited after it was billed in advance" do
        let(:billing_scope) { "cycle" }
        let(:change_at) { Time.utc(2027, 1, 15) }
        let(:rate_card) { create(:rate_card, :advance, organization:, product:, currency: "USD", proration: true) }
        let(:old_rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: clock, rate_properties: {"amount" => "31"}) }
        let(:rate) { new_rate }
        let(:renewal) { BillingOperations::ScheduleService.call!(customer:, timestamp: Time.current).billing_operations.sole }
        let(:invoice) { BillingOperations::ProcessService.call!(customer:, timestamp: Time.current).invoices.sole }

        before do
          travel_to(clock)
          renewal
          invoice
        end

        it "reconciles the completed renewal even though its coverage and rate references match" do
          original_attributes = renewal.reload.attributes
          saved_segments = renewal.segments.pluck(:started_at, :ended_at, :rate_card_rate_id, :proration_ratio)
          expect(invoice.fees.order(:amount_cents).pluck(:amount_cents)).to eq([1400, 3400]) # $31 * 14/31 days, then $62 * 17/31 days.
          expect(invoice.total_amount_cents).to eq(4800)

          travel_to(clock + 1.hour)
          RateCardRates::UpdateService.call!(rate_card_rate: rate, params: {rate_properties: {"amount" => "124"}})
          expect { result }.to change(reconciliations, :count).by(1)
          expect(result).to be_success

          reconciliation = reconciliations.sole
          expect(reconciliation).to have_attributes(
            target_cycle_started_at: clock, coverage_started_at: clock, coverage_ended_at: next_cycle_start, invoice_id: nil
          )
          expect(reconciliation.segments.pluck(:started_at, :ended_at, :rate_card_rate_id, :proration_ratio)).to eq(saved_segments)
          expect(renewal.reload.attributes).to eq(original_attributes)
          expect(invoice.reload.total_amount_cents).to eq(4800)
        end
      end

      context "when a pending renewal was saved after the rate was postponed" do
        let(:change_at) { Time.utc(2027, 1, 15) }
        let(:revised_start) { Time.utc(2027, 1, 20) }
        let(:rate) do
          travel_to(clock)
          rate_to_postpone = new_rate
          travel_to(clock + 1.hour)
          RateCardRates::UpdateService.call!(rate_card_rate: rate_to_postpone, params: {effective_from: revised_start}).rate_card_rate
        end
        let(:renewals) { BillingOperations::ScheduleService.call!(customer:, timestamp: Time.current).billing_operations }

        before do
          travel_to(revised_start)
          renewals
        end

        %w[cycle segment].each do |scope|
          context "with #{scope} scope" do
            let(:billing_scope) { scope }

            it "does not use renewals created after the rate edit as source candidates" do
              saved_segments = renewals.flat_map { it.segments.pluck(:started_at, :ended_at, :rate_card_rate_id) }
              expect(saved_segments).to eq([
                [clock, revised_start, old_rate.id],
                [revised_start, next_cycle_start, rate.id]
              ])
              expect(renewals.map(&:created_at)).to all(be > rate.updated_at)
              expect { result }.not_to change(reconciliations, :count)
              expect(result).to be_success
            end
          end
        end
      end
    end

    context "with saved coverage that is ineligible for reconciliation" do
      let(:reason) { :periodic_continuation }
      let(:cancellation) { {} }
      let(:renewal) do
        create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card: card,
          action_type: card.periodic_billing_action, reason:, billing_at: contract.started_at,
          target_cycle_started_at: contract.started_at, **cancellation)
      end
      let(:rate) do
        renewal
        super()
      end

      shared_examples "an excluded renewal" do
        it "does not reconcile the saved coverage" do
          expect(renewal.segments.sole.ended_at).to eq(clock)
          expect { result }.not_to change(BillingOperation, :count)
          expect(result).to be_success
        end
      end

      context "when the renewal was cancelled" do
        let(:cancellation) { {cancelled_at: Time.current, cancellation_reason: :rate_change} }

        it_behaves_like "an excluded renewal"
      end

      context "when the renewal is for late payment" do
        let(:reason) { :late_payment }

        it_behaves_like "an excluded renewal"
      end

      context "when the renewal is recurring metered advance" do
        let(:metric) { create(:sum_billable_metric, organization:, recurring: true, field_name: "quantity") }
        let(:product) { create(:product, :metered, organization:, billable_metric: metric) }

        it_behaves_like "an excluded renewal"
      end
    end
  end

  context "with metered arrears" do
    let(:product) { create(:product, organization:) }

    it "wakes the clock" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(effective_from)
    end
  end

  context "when the clock is earlier than the change" do
    let(:clock) { Time.utc(2026, 11, 1) }

    it "corrects the stale wake to the first unbilled close" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(effective_from)
    end
  end

  context "when the clock equals the change" do
    let(:clock) { effective_from }

    it "leaves the clock unchanged" do
      expect { result }.not_to change { card.reload.updated_at }
      expect(result).to be_success
      expect(card.next_billing_at).to eq(clock)
    end
  end

  context "when the clock is nil" do
    let(:clock) { nil }

    it "wakes an exhausted periodic card" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(effective_from)
    end

    context "when the final coverage has already closed" do
      let(:contract) do
        create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1), ended_at: Time.utc(2026, 11, 10))
      end

      before do
        create(:billing_operation, organization:, customer:, contract_rate_card: card,
          action_type: BillingOperation::ACTION_TYPES.fetch(:close_fixed_arrears), reason: "periodic_continuation",
          billing_at: Time.utc(2026, 11, 10), target_cycle_started_at: Time.utc(2026, 11, 1),
          coverage_started_at: Time.utc(2026, 11, 1), coverage_ended_at: Time.utc(2026, 11, 10),
          processed_at: Time.utc(2026, 11, 10))
      end

      it "keeps the clock nil when no obligation remains" do
        expect(result).to be_success
        expect(card.reload.next_billing_at).to be_nil
      end
    end
  end

  context "when the card has no periodic action" do
    let(:product) { create(:product, organization:) }
    let(:billing_timing) { "advance" }
    let(:clock) { nil }

    it "leaves the clock nil" do
      expect(card.periodic_billing_action).to be_nil
      expect(result).to be_success
      expect(card.reload.next_billing_at).to be_nil
      expect(BillingOperation.where(contract_rate_card: card)).to be_empty
    end

    context "with an existing clock" do
      let(:clock) { Time.utc(2026, 12, 1) }

      it "clears the stale wake" do
        expect(result).to be_success
        expect(card.reload.next_billing_at).to be_nil
      end
    end
  end

  context "when the rate was discarded" do
    before { rate.discard! }

    it "replans from the remaining rate" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
    end
  end

  context "when the rate belongs to another organization" do
    let(:rate) { create(:rate_card_rate) }

    it "does not change the card" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(clock)
    end
  end

  context "when the contract has not started" do
    let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 13)) }

    it "does not change the card" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(clock)
    end
  end

  context "when the contract is canceled" do
    let(:contract) { create(:contract, :canceled, organization:, customer:, started_at: Time.utc(2026, 11, 1)) }

    it "does not change the card" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(clock)
    end
  end

  context "when termination wins the customer lock" do
    before do
      allow(Customers::LockService).to receive(:call!).and_wrap_original do |original, **kwargs, &block|
        contract.update!(status: :terminated, terminated_at: Time.current)
        original.call(**kwargs, &block)
      end
    end

    it "leaves the clock to termination planning" do
      expect(result).to be_success
      expect(card.reload.next_billing_at).to eq(clock)
    end
  end

  context "when the customer is missing" do
    subject(:result) { described_class.call(customer: nil, rate_card_rate_id: rate.id) }

    it "returns a not found failure" do
      expect(result).to be_failure
    end
  end

  context "when resetting the clock fails" do
    let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_schedule") }

    before do
      allow(ContractRateCards::ResetBillingClockService).to receive(:call!)
        .and_raise(failure.error)
    end

    it "returns the reset failure without changing the clock" do
      expect(result).to be_failure
      expect(result.error).to eq(failure.error)
      expect(card.reload.next_billing_at).to eq(clock)
    end
  end
end
