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
        external_id: "edge-contract", external_customer_id: customer.external_id,
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
    it "replans the first due date and catches up coverage before the existing December operation" do
      expect(rate_card.rates.count).to eq(1)
      operation = first_operation
      expect(operation).to have_attributes(
        action_type: BillingOperation::ACTION_TYPES.fetch(:renew_fixed_advance),
        billing_at: december, coverage_started_at: december, coverage_ended_at: january,
        processed_at: nil, cancelled_at: nil
      )
      expect(card.reload.next_billing_at).to eq(december)

      travel_to(Time.utc(2026, 11, 12)) do
        api_call(perform_jobs: false) do
          post_with_token(organization, "/api/v2/rate_cards/edge-card/rates", {rate: {
            code: "new", effective_from: change_at.iso8601, rate_model: "standard",
            billing_interval_count: 1, billing_interval_unit: "month", rate_properties: {amount: "60"}
          }})
        end
        new_rate = rate_card.rates.find_by!(code: "new")
        apply_rate_jobs(new_rate)
        expect(card.reload.next_billing_at).to eq(change_at)
        expect(operation.reload).to have_attributes(
          billing_at: december, coverage_started_at: december, coverage_ended_at: january,
          processed_at: nil, cancelled_at: nil
        )
        expect(card.billing_operations.where(action_type: BillingOperation::ACTION_TYPES.fetch(:reconcile_advance_coverage))).to be_empty
      end

      travel_to(december + 5.minutes) do
        Clock::ScheduleBillingOperationsJob.perform_now
        perform_all_enqueued_jobs(except: [BillingOperations::ProcessJob])
        2.times { BillingOperations::ProcessJob.perform_now(customer.id) }

        completed = card.billing_operations.completed.periodic.order(:coverage_started_at).to_a
        expect(completed.map { [it.coverage_started_at, it.coverage_ended_at] }).to eq([
          [change_at, december], [december, january]
        ])
        expect(completed.last.id).to eq(operation.id)
        expect(completed.map { it.invoice.total_amount_cents }).to eq([3_200, 3_000]) # $60 * 16/30 days; then $30 for December.
        expect(operation.reload.processed_at).to be_present
        expect(card.reload.next_billing_at).to eq(january)
        expect(card.billing_operations.where(action_type: BillingOperation::ACTION_TYPES.fetch(:reconcile_advance_coverage))).to be_empty
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

  context "when a prepaid future price moves later" do
    let(:initial_rates) do
      [
        {code: "old", effective_from: start_at.iso8601, rate_model: "standard",
         billing_interval_count: 1, billing_interval_unit: "month", rate_properties: {amount: "30"}},
        {code: "new", effective_from: change_at.iso8601, rate_model: "standard",
         billing_interval_count: 1, billing_interval_unit: "month", rate_properties: {amount: "60"}}
      ]
    end

    it "queues reconciliation for the previously priced November coverage" do
      operation = first_operation
      invoice = operation.invoice
      expect(operation).to have_attributes(coverage_started_at: start_at, coverage_ended_at: december, processed_at: start_at + 5.minutes)
      expect(invoice.total_amount_cents).to eq(4_600) # $30 * 14/30 + $60 * 16/30 days.
      expect(invoice.fees.order(:amount_cents).pluck(:amount_cents)).to eq([1_400, 3_200])
      expect(card.reload.next_billing_at).to eq(december)
      reconciliation_type = BillingOperation::ACTION_TYPES.fetch(:reconcile_advance_coverage)
      expect(card.billing_operations.where(action_type: reconciliation_type)).to be_empty
      snapshot = operation.attributes.slice("coverage_started_at", "coverage_ended_at", "processed_at", "invoice_id")
      fee_ids = invoice.fees.order(:id).pluck(:id)

      travel_to(Time.utc(2026, 11, 12)) do
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
        expect(card.billing_operations.pending.where(action_type: reconciliation_type)).to contain_exactly(
          have_attributes(coverage_started_at: start_at, coverage_ended_at: december, reason: "rate_change")
        )
      end
    end
  end
end
