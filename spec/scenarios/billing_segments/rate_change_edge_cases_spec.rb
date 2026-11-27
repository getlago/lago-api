# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Fixed advance rate change edge cases" do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { organization.customers.find_by!(external_id: "edge-customer") }
  let(:contract) { organization.contracts.find_by!(external_id: "edge-contract") }
  let(:card) { contract.applied_rate_cards.sole }
  let(:rate_card) { organization.rate_cards.find_by!(code: "edge-card") }
  let(:first_operation) { card.billing_operations.periodic.sole }
  let(:start_at) { Time.utc(2026, 11, 1) }
  let(:change_at) { Time.utc(2026, 11, 15) }
  let(:december) { Time.utc(2026, 12, 1) }
  let(:january) { Time.utc(2027, 1, 1) }
  let(:billing_scope) { "cycle" }
  let(:initial_rates) do
    [{code: "old", effective_from: december.iso8601, rate_model: "standard",
      billing_interval_count: 1, billing_interval_unit: "month", rate_properties: {amount: "30"}}]
  end

  around do |example|
    travel_to(Time.utc(2026, 10, 31))
    example.run
  ensure
    travel_back
  end

  before do
    stub_pdf_generation
    create_or_update_customer({external_id: "edge-customer", timezone: "UTC", currency: "USD"})
    api_call do
      post_with_token(organization, "/api/v2/products", {product: {
        name: "Fixed", code: "edge-product", product_type: "fixed"
      }})
    end
    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: "Card", code: "edge-card", product_code: "edge-product", currency: "USD",
        billing_timing: "advance", proration: true, rates: initial_rates
      }})
    end
    api_call do
      post_with_token(organization, "/api/v2/plans", {plan: {name: "Plan", code: "edge-plan", currency: "USD"}})
    end
    api_call do
      post_with_token(organization, "/api/v2/plans/edge-plan/applied_rate_cards", {
        applied_rate_card: {rate_card_code: "edge-card", units: 1}
      })
    end
    api_call do
      post_with_token(organization, "/api/v2/contracts", {contract: {
        code: "edge-contract", external_id: "edge-contract", external_customer_id: customer.external_id,
        plan_code: "edge-plan", started_at: start_at.iso8601
      }})
    end
    if billing_scope == "segment"
      api_call do
        put_with_token(organization, "/api/v2/contracts/edge-contract/applied_rate_cards/edge-card", {
          applied_rate_card: {billing_scope:}
        })
      end
    end
    travel_to(start_at + 5.minutes) { perform_enqueued_jobs { Clock::ActivateContractsJob.perform_now } }
  end

  def apply_rate_jobs(rate)
    expect(RateCardRates::ApplyRateChangeJob).to have_been_enqueued.with(rate.id)
    perform_all_enqueued_jobs(only: [RateCardRates::ApplyRateChangeJob])
    expect(BillingOperations::ApplyRateChangeJob).to have_been_enqueued.with(customer.id, rate.id)
    perform_all_enqueued_jobs(only: [BillingOperations::ApplyRateChangeJob])
  end

  shared_examples "an earlier first price" do
    it "replans the first due date and catches up coverage through December" do
      expect(rate_card.rates.count).to eq(1)
      expect(card.billing_operations).to be_empty
      expect(card.reload.next_billing_at).to eq(december)

      travel_to(Time.utc(2026, 11, 12)) do
        expect(contract.reload).to be_active
        expect(rate_card.rates.sole).to be_pending
        api_call(perform_jobs: false) do
          post_with_token(organization, "/api/v2/rate_cards/edge-card/rates", {rate: {
            code: "new", effective_from: change_at.iso8601, rate_model: "standard",
            billing_interval_count: 1, billing_interval_unit: "month", rate_properties: {amount: "60"}
          }})
        end
        new_rate = rate_card.rates.find_by!(code: "new")
        expect(new_rate).to be_pending
        apply_rate_jobs(new_rate)
        expect(card.reload.next_billing_at).to eq(change_at)
        expect(card.billing_operations).to be_empty
      end

      travel_to(december + 5.minutes) do
        Clock::ScheduleBillingOperationsJob.perform_now
        perform_all_enqueued_jobs(except: [BillingOperations::ProcessJob])
        2.times { BillingOperations::ProcessJob.perform_now(customer.id) }

        completed = card.billing_operations.completed.periodic.order(:coverage_started_at).to_a
        expect(completed.map { [it.coverage_started_at, it.coverage_ended_at] }).to eq([
          [change_at, december], [december, january]
        ])
        expect(completed.map { it.invoice.total_amount_cents }).to eq([3_200, 3_000]) # $60 * 16/30 days; then $30 for December.
        expect(card.reload.next_billing_at).to eq(january)
        expect(card.billing_operations.pending).to be_empty
      end
    end
  end

  context "when the first priced coverage starts earlier" do
    context "with cycle billing" do
      include_examples "an earlier first price"
    end

    context "with segment billing" do
      let(:billing_scope) { "segment" }

      include_examples "an earlier first price"
    end
  end

  it "moves the first cycle renewal when its only price is postponed" do
    moved_to = Time.utc(2026, 12, 15)
    expect(card.next_billing_at).to eq(december)

    travel_to(Time.utc(2026, 11, 12)) do
      api_call do
        put_with_token(organization, "/api/v2/rate_cards/edge-card/rates/old", {rate: {effective_from: moved_to.iso8601}})
      end
    end

    expect(card.reload.next_billing_at).to eq(moved_to)
    expect(card.billing_operations).to be_empty
  end

  context "with a second rate scheduled for November 15" do
    let(:initial_rates) do
      [
        {code: "old", effective_from: start_at.iso8601, rate_model: "standard",
         billing_interval_count: 1, billing_interval_unit: "month", rate_properties: {amount: "30"}},
        {code: "new", effective_from: change_at.iso8601, rate_model: "standard",
         billing_interval_count: 1, billing_interval_unit: "month", rate_properties: {amount: "60"}}
      ]
    end

    it "reconciles an edit to a covered rate exactly once when all segment boundaries stay unchanged" do
      operation = first_operation
      expect(card.billing_operations.sole).to eq(operation)
      expect(operation).to have_attributes(coverage_started_at: start_at, coverage_ended_at: december)
      expect(operation.processed_at).to be_present
      original = operation.attributes
      original_segments = operation.segments.map(&:attributes)
      fields = %i[started_at ended_at rate_card_rate_id]
      rate = rate_card.rates.find_by!(code: "new")
      segments = [[start_at, change_at, rate_card.rates.find_by!(code: "old").id], [change_at, december, rate.id]]
      expect(operation.segments.pluck(*fields)).to eq(segments)

      travel_to(Time.utc(2026, 11, 12)) do
        api_call(perform_jobs: false) do
          put_with_token(organization, "/api/v2/rate_cards/edge-card/rates/new", {rate: {rate_properties: {amount: "40"}}})
        end
        apply_rate_jobs(rate)
        reconciliation = card.billing_operations.pending.sole
        expect(reconciliation).to have_attributes(action_type: "reconcile_advance_coverage", reason: "rate_change",
          coverage_started_at: start_at, coverage_ended_at: december)
        expect(reconciliation.segments.pluck(*fields)).to eq(segments)

        BillingOperations::ApplyRateChangeJob.perform_now(customer.id, rate.id)
        expect(card.billing_operations.pending.pluck(:id)).to eq([reconciliation.id])
        expect(card.billing_operations.pluck(:id)).to contain_exactly(operation.id, reconciliation.id)
      end

      expect(operation.reload.attributes).to eq(original)
      expect(operation.segments.map(&:attributes)).to eq(original_segments)
    end

    context "with segment billing when the new rate moves from Nov 15 to Nov 20" do
      let(:billing_scope) { "segment" }
      let(:moved_to) { Time.utc(2026, 11, 20) }
      let(:old_rate) { rate_card.rates.find_by!(code: "old") }
      let(:new_rate) { rate_card.rates.find_by!(code: "new") }

      it "snapshots the revised cycle and moves the next periodic billing date to Nov 20" do
        expect(new_rate.effective_from).to eq(change_at)
        expect(card.next_billing_at).to eq(change_at)
        expect(first_operation.segments.pluck(:started_at, :ended_at, :rate_card_rate_id)).to eq([[start_at, change_at, old_rate.id]])
        expect(first_operation.invoice.total_amount_cents).to eq(1_400) # $30 × 14/30 days.

        travel_to(Time.utc(2026, 11, 12))
        api_call do
          put_with_token(organization, "/api/v2/rate_cards/edge-card/rates/new", {rate: {effective_from: moved_to.iso8601}})
        end

        # The full-cycle snapshot covers Nov 1–19 at the old rate and Nov 20–30 at the new rate.
        reconciliation = card.billing_operations.pending.sole
        expect(reconciliation).to have_attributes(action_type: "reconcile_advance_coverage", reason: "rate_change",
          target_cycle_started_at: start_at, coverage_started_at: start_at, coverage_ended_at: december)
        expect(reconciliation.segments.pluck(:started_at, :ended_at, :rate_card_rate_id, :proration_ratio)).to eq([
          [start_at, moved_to, old_rate.id, (19.to_d / 30).round(10)],
          [moved_to, december, new_rate.id, (11.to_d / 30).round(10)]
        ])
        expect(card.reload.next_billing_at).to eq(moved_to)

        travel_to(change_at + 5.minutes) { perform_enqueued_jobs { Clock::ScheduleBillingOperationsJob.perform_now } }
        completed = card.billing_operations.completed.periodic.order(:coverage_started_at)
        expect(card.billing_operations.periodic.pluck(:id)).to eq([first_operation.id])
        expect(card.reload.next_billing_at).to eq(moved_to)

        travel_to(moved_to + 5.minutes) { perform_enqueued_jobs { Clock::ScheduleBillingOperationsJob.perform_now } }
        billed = completed.map do |operation|
          segment = operation.segments.sole
          fee = operation.invoice.fees.sole
          [segment.started_at, segment.ended_at, fee.rate_card_rate_id, fee.amount_cents]
        end
        expect(billed).to eq([
          [start_at, change_at, old_rate.id, 1_400],
          [moved_to, december, new_rate.id, 2_200] # $60 × 11/30 days.
        ])
        expect(reconciliation.reload).to have_attributes(processed_at: nil, cancelled_at: nil, invoice_id: nil)
      end
    end

    context "when a rate postponement extends a completed segment" do
      let(:billing_scope) { "segment" }
      let(:old_rate) { rate_card.rates.find_by!(code: "old") }
      let(:new_rate) { rate_card.rates.find_by!(code: "new") }
      let(:segment_fields) { %i[started_at ended_at rate_card_rate_id] }

      shared_examples "reconciliation of the completed November segment" do |scheduler_first: false|
        it "records the revised November cycle separately from the next renewal" do
          expect(first_operation).to have_attributes(action_type: "renew_fixed_advance", coverage_started_at: start_at,
            coverage_ended_at: change_at, processed_at: start_at + 5.minutes)
          expect(first_operation.segments.pluck(*segment_fields)).to eq([[start_at, change_at, old_rate.id]])
          expect(card.next_billing_at).to eq(change_at)

          travel_to(Time.utc(2026, 11, 12))
          api_call(perform_jobs: false) do
            put_with_token(organization, "/api/v2/rate_cards/edge-card/rates/new", {rate: {effective_from: moved_to.iso8601}})
          end
          expect(new_rate.effective_from).to eq(moved_to)
          expect(card.billing_operations.pluck(:id)).to eq([first_operation.id])

          if scheduler_first
            travel_to(change_at + 5.minutes)
            perform_enqueued_jobs { Clock::ScheduleBillingOperationsJob.perform_now }
            expect(card.reload.next_billing_at).to eq(moved_to)
            expect(card.billing_operations.pluck(:id)).to eq([first_operation.id])
          end
          apply_rate_jobs(new_rate)

          reconciliation = card.billing_operations.pending.sole
          expect(reconciliation).to have_attributes(action_type: "reconcile_advance_coverage", reason: "rate_change",
            target_cycle_started_at: start_at, coverage_started_at: start_at, coverage_ended_at: december)
          expected_segments = [[start_at, next_renewal, old_rate.id]]
          expected_segments << [next_renewal, december, new_rate.id] if next_renewal < december
          expect(reconciliation.segments.pluck(*segment_fields)).to eq(expected_segments)
          expect(card.billing_operations.periodic.pluck(:id)).to eq([first_operation.id])
          expect(card.reload.next_billing_at).to eq(next_renewal)

          travel_to(next_renewal + 5.minutes) { perform_enqueued_jobs { Clock::ScheduleBillingOperationsJob.perform_now } }
          renewal = card.billing_operations.completed.periodic.where.not(id: first_operation.id).sole
          expect(renewal).to have_attributes(action_type: "renew_fixed_advance", reason: "periodic_continuation",
            coverage_started_at: next_renewal, coverage_ended_at: renewal_end)
          expect(renewal.segments.pluck(*segment_fields)).to eq([[next_renewal, renewal_end, renewal_rate.id]])
          expect(first_operation.reload).to have_attributes(coverage_started_at: start_at, coverage_ended_at: change_at,
            processed_at: start_at + 5.minutes)
          expect(first_operation.segments.pluck(*segment_fields)).to eq([[start_at, change_at, old_rate.id]])
          expect(card.billing_operations.pending.pluck(:id)).to eq([reconciliation.id])
          expect(card.reload.next_billing_at).to eq(renewal_end)
        end
      end

      context "when the new rate moves across the cycle boundary to Dec 15" do
        let(:moved_to) { Time.utc(2026, 12, 15) }
        let(:next_renewal) { december }
        let(:renewal_end) { moved_to }
        let(:renewal_rate) { old_rate }

        include_examples "reconciliation of the completed November segment"
      end

      context "when the Nov 15 scheduler runs before the worker for the move to Nov 20" do
        let(:moved_to) { Time.utc(2026, 11, 20) }
        let(:next_renewal) { moved_to }
        let(:renewal_end) { december }
        let(:renewal_rate) { new_rate }

        include_examples "reconciliation of the completed November segment", scheduler_first: true
      end
    end

    it "records only the latest schedule when the same rate is edited twice before the customer job runs" do
      rate = rate_card.rates.find_by!(code: "new")
      first_date = Time.utc(2026, 11, 20)
      latest_date = Time.utc(2026, 12, 15)
      [first_date, latest_date].each_with_index do |date, index|
        travel_to(start_at + (index + 1).days)
        api_call(perform_jobs: false) do
          put_with_token(organization, "/api/v2/rate_cards/edge-card/rates/new", {rate: {effective_from: date.iso8601}})
        end
        perform_all_enqueued_jobs(only: [RateCardRates::ApplyRateChangeJob])
      end

      expect(BillingOperations::ApplyRateChangeJob).to have_been_enqueued.with(customer.id, rate.id).at_least(:once)
      perform_all_enqueued_jobs(only: [BillingOperations::ApplyRateChangeJob])
      BillingOperations::ApplyRateChangeJob.perform_now(customer.id, rate.id)

      reconciliation = card.billing_operations.where(action_type: "reconcile_advance_coverage").sole
      expect(reconciliation).to have_attributes(coverage_started_at: start_at, coverage_ended_at: december)
      expect(reconciliation.segments.pluck(:started_at, :ended_at, :rate_card_rate_id)).to eq([
        [start_at, december, rate_card.rates.find_by!(code: "old").id]
      ])
    end

    it "keeps the completed snapshot and reconciles the revised November cycle" do
      operation = first_operation
      invoice = operation.invoice
      old_rate = rate_card.rates.find_by!(code: "old")
      moved_rate = rate_card.rates.find_by!(code: "new")
      segment_fields = %i[position started_at ended_at rate_card_rate_id proration_ratio]
      purchased_segments = [
        [0, start_at, change_at, old_rate.id, (14.to_d / 30).round(10)],
        [1, change_at, december, moved_rate.id, (16.to_d / 30).round(10)]
      ]
      expect(operation).to have_attributes(coverage_started_at: start_at, coverage_ended_at: december, processed_at: start_at + 5.minutes)
      expect(operation.segments.pluck(*segment_fields)).to eq(purchased_segments)
      expect(invoice.total_amount_cents).to eq(4_600) # $30 * 14/30 + $60 * 16/30 days.
      expect(invoice.fees.order(:amount_cents).pluck(:amount_cents)).to eq([1_400, 3_200])
      expect(card.reload.next_billing_at).to eq(december)
      reconciliation_type = BillingOperation::ACTION_TYPES.fetch(:reconcile_advance_coverage)
      expect(card.billing_operations.where(action_type: reconciliation_type)).to be_empty
      snapshot = operation.attributes.slice("coverage_started_at", "coverage_ended_at", "processed_at", "invoice_id")
      fee_ids = invoice.fees.order(:id).pluck(:id)

      travel_to(Time.utc(2026, 11, 12)) do
        rate = rate_card.rates.find_by!(code: "new")
        expect(contract.reload).to be_active
        expect(card.billing_scope).to eq("cycle")
        expect(rate_card.rates.find_by!(code: "old")).to be_active
        expect(rate).to be_pending
        expect(invoice.fees.find_by!(rate_card_rate_id: rate.id).amount_cents).to eq(3_200)
        api_call(perform_jobs: false) do
          put_with_token(organization, "/api/v2/rate_cards/edge-card/rates/new", {
            rate: {effective_from: Time.utc(2026, 12, 15).iso8601}
          })
        end
        rate = rate_card.rates.find_by!(code: "new")
        expect(rate.effective_from).to eq(Time.utc(2026, 12, 15))
        apply_rate_jobs(rate)

        expect(operation.reload.attributes.slice(*snapshot.keys)).to eq(snapshot)
        expect(invoice.reload.total_amount_cents).to eq(4_600)
        expect(invoice.fees.order(:id).pluck(:id)).to eq(fee_ids)
        expect(card.reload.next_billing_at).to eq(december)
        expect(operation.segments.pluck(*segment_fields)).to eq(purchased_segments)
        reconciliation = card.billing_operations.pending.where(action_type: reconciliation_type).sole
        expect(reconciliation).to have_attributes(coverage_started_at: start_at, coverage_ended_at: december,
          target_cycle_started_at: start_at, billing_at: start_at, reason: "rate_change", invoice_id: nil)
        expect(reconciliation.segments.pluck(*segment_fields)).to eq([
          [0, start_at, december, old_rate.id, 1]
        ])
      end
    end
  end
end
