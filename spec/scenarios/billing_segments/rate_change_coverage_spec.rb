# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Billing operation coverage across a rate change" do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { organization.customers.find_by!(external_id: "coverage-customer") }
  let(:contract) { organization.contracts.find_by!(external_id: "coverage-contract") }
  let(:card) { contract.applied_rate_cards.sole }
  let(:rate_card) { organization.rate_cards.find_by!(code: "coverage-card") }
  let(:new_rate) { rate_card.rates.find_by!(code: "new") }
  let(:start_at) { Time.utc(2026, 11, 1) }
  let(:change_at) { Time.utc(2026, 11, 15) }
  let(:end_at) { Time.utc(2026, 12, 1) }
  let(:billing_scope) { "cycle" }
  let(:product_type) { "fixed" }
  let(:billing_timing) { "advance" }
  let(:recurring) { false }
  let(:display_on_invoice) { true }
  let(:regroup_paid_fees) { nil }
  let(:action_type) { "renew_fixed_advance" }
  let(:initially_completed) { true }
  let(:first_operation) { card.billing_operations.where(action_type:).sole }

  around do |example|
    travel_to(Time.utc(2026, 10, 31))
    example.run
  ensure
    travel_back
  end

  before do
    stub_pdf_generation
    create_or_update_customer({external_id: "coverage-customer", timezone: "UTC", currency: "USD"})
    if product_type == "metered"
      create_metric({name: "Usage", code: "coverage-usage", aggregation_type: "sum_agg",
                     field_name: "quantity", recurring:})
    end
    api_call do
      post_with_token(organization, "/api/v2/products", {product: {
        name: "Product", code: "coverage-product", product_type:,
        billable_metric_code: (product_type == "metered") ? "coverage-usage" : nil
      }.compact})
    end
    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: "Card", code: "coverage-card", product_code: "coverage-product", currency: "USD",
        billing_timing:, proration: product_type == "fixed", display_on_invoice:, regroup_paid_fees:,
        rates: [{
          code: "old", effective_from: start_at.iso8601, rate_model: "standard",
          billing_interval_count: 1, billing_interval_unit: "month", rate_properties: {amount: "30"}
        }]
      }.compact})
    end
    api_call do
      post_with_token(organization, "/api/v2/plans", {plan: {name: "Plan", code: "coverage-plan", currency: "USD"}})
    end
    api_call do
      post_with_token(organization, "/api/v2/plans/coverage-plan/applied_rate_cards", {
        applied_rate_card: {rate_card_code: "coverage-card", units: 1}
      })
    end
    api_call do
      post_with_token(organization, "/api/v2/contracts", {contract: {
        external_id: "coverage-contract", external_customer_id: customer.external_id,
        plan_code: "coverage-plan", started_at: start_at.iso8601
      }})
    end
    if billing_scope == "segment"
      api_call do
        put_with_token(organization, "/api/v2/contracts/coverage-contract/applied_rate_cards/coverage-card", {
          applied_rate_card: {billing_scope:}
        })
      end
    end
    travel_to(start_at + 5.minutes) { perform_enqueued_jobs { Clock::ActivateContractsJob.perform_now } }
  end

  def add_rate_and_apply_change
    travel_to(Time.utc(2026, 11, 12)) do
      api_call(perform_jobs: false) do
        post_with_token(organization, "/api/v2/rate_cards/coverage-card/rates", {rate: {
          code: "new", effective_from: change_at.iso8601, rate_model: "standard",
          billing_interval_count: 1, billing_interval_unit: "month", rate_properties: {amount: "60"}
        }})
      end
      expect(new_rate).to be_present
      expect(RateCardRates::ApplyRateChangeJob).to have_been_enqueued.with(new_rate.id)
      perform_all_enqueued_jobs(only: [RateCardRates::ApplyRateChangeJob])
      expect(BillingOperations::ApplyRateChangeJob).to have_been_enqueued.with(customer.id, new_rate.id)
      perform_all_enqueued_jobs(only: [BillingOperations::ApplyRateChangeJob])
    end
  end

  shared_examples "rate change preserves the stored operation" do
    it "preserves the first operation's coverage and state at the rate-change job stage" do
      expect(rate_card.rates.count).to eq(1)
      operation = first_operation
      snapshot = operation.attributes.slice("id", "coverage_started_at", "coverage_ended_at", "processed_at",
        "cancelled_at", "invoice_id")
      expect(operation).to have_attributes(coverage_started_at: start_at, coverage_ended_at: end_at)
      expect(operation.processed_at.present?).to eq(initially_completed)
      expect(card.billing_operations.where(action_type: "reconcile_advance_coverage")).to be_empty
      initial_clock = card.reload.next_billing_at

      if product_type == "metered"
        travel_to(Time.utc(2026, 11, 10, 12)) do
          create_event({external_contract_id: contract.external_id, code: "coverage-usage",
                        timestamp: Time.current.to_i, properties: {quantity: "1"}})
        end
      end
      add_rate_and_apply_change

      expect(operation.reload.attributes.slice(*snapshot.keys)).to eq(snapshot)
      expected_clock = if initially_completed || billing_scope == "cycle"
        snapshot.fetch("coverage_ended_at")
      else
        change_at
      end
      expect(card.reload.next_billing_at).to eq(expected_clock)
      if action_type == "renew_fixed_advance"
        expect(initial_clock).to eq(snapshot.fetch("coverage_ended_at"))
        expect(card.billing_operations.pending.where(action_type: "reconcile_advance_coverage", reason: "rate_change").count).to eq(1)
      else
        expect(card.billing_operations.where(action_type: "reconcile_advance_coverage")).to be_empty
      end
    end
  end

  shared_examples "fixed advance continuation" do
    it "continues at the stored coverage end without billing the covered rate-change slice" do
      expect(rate_card.rates.count).to eq(1)
      operation = first_operation
      expect(operation).to have_attributes(coverage_started_at: start_at, coverage_ended_at: end_at)
      expect(operation.processed_at).to be_present
      expect(Fee.where(contract:, fee_type: :product).pluck(:amount_cents)).to eq([3_000])
      covered_until = operation.coverage_ended_at
      snapshot = operation.attributes.slice("id", "coverage_started_at", "coverage_ended_at", "processed_at",
        "cancelled_at", "invoice_id")

      add_rate_and_apply_change
      reconciliation = card.billing_operations.find_by!(
        action_type: BillingOperation::ACTION_TYPES.fetch(:reconcile_advance_coverage)
      )
      travel_to(end_at + 5.minutes) do
        Clock::ScheduleBillingOperationsJob.perform_now
        perform_all_enqueued_jobs
        expect(Fee.where(contract:, fee_type: :product).order(:created_at).pluck(:amount_cents)).to eq([3_000, 6_000])
        renewal = card.billing_operations.where(
          action_type: BillingOperation::ACTION_TYPES.fetch(:renew_fixed_advance), coverage_started_at: covered_until
        ).sole
        expect(card.billing_operations.pluck(:id)).to match_array([operation.id, reconciliation.id, renewal.id])
        expect(operation.reload.attributes.slice(*snapshot.keys)).to eq(snapshot)
        expect(reconciliation.reload).to have_attributes(
          processed_at: nil, invoice_id: nil,
          coverage_started_at: (billing_scope == "cycle") ? start_at : change_at, coverage_ended_at: covered_until
        )
        expect(renewal).to have_attributes(
          processed_at: Time.current, coverage_started_at: covered_until, coverage_ended_at: Time.utc(2027, 1, 1)
        )
        expect(renewal.invoice).to be_present
        expect(renewal.invoice.fees.where(fee_type: :product).pluck(:amount_cents)).to eq([6_000])
        expect(card.reload.next_billing_at).to eq(Time.utc(2027, 1, 1))
        expect(CreditNote.where(customer:)).to be_empty
      end
    end
  end

  shared_examples "both billing scopes" do
    context "with cycle billing" do
      include_examples "rate change preserves the stored operation"
    end

    context "with segment billing" do
      let(:billing_scope) { "segment" }

      include_examples "rate change preserves the stored operation"
    end
  end

  shared_examples "arrears coverage after the rate change" do
    it "invoices the uncovered portions on both sides of the new rate" do
      operation = first_operation
      expect(operation).to have_attributes(coverage_started_at: start_at, coverage_ended_at: end_at, processed_at: nil)
      if product_type == "metered"
        travel_to(Time.utc(2026, 11, 10, 12)) do
          create_event({external_contract_id: contract.external_id, code: "coverage-usage",
                        timestamp: Time.current.to_i, properties: {quantity: "1"}})
        end
      end
      add_rate_and_apply_change
      if product_type == "metered"
        travel_to(Time.utc(2026, 11, 20, 12)) do
          create_event({external_contract_id: contract.external_id, code: "coverage-usage",
                        timestamp: Time.current.to_i, properties: {quantity: "1"}}, perform_jobs: false)
        end
      end
      travel_to(end_at + 5.minutes) do
        Clock::ScheduleBillingOperationsJob.perform_now
        perform_all_enqueued_jobs
        fees = Fee.where(contract:, fee_type: :product).order(:created_at).to_a
        if product_type == "fixed"
          # $30 * 14/30 days and $60 * 16/30 days.
          expect(fees.map(&:amount_cents).sort).to eq([1_400, 3_200])
        else
          # One unit before the change at $30 and one after at $60.
          expect(fees.map(&:amount_cents).sort).to eq([3_000, 6_000])
        end
        expect(fees.map { |fee| fee.rate_card_rate.code }.sort).to eq(%w[new old])
        expect(fees.sort_by { |fee| fee.rate_card_rate.effective_from }.map { |fee|
          [fee.properties["from_datetime"], fee.properties["to_datetime"]]
        }).to eq([
          [start_at.iso8601(6), BillingSegment.inclusive_end(change_at).iso8601(6)],
          [change_at.iso8601(6), BillingSegment.inclusive_end(end_at).iso8601(6)]
        ])
        coverage = card.billing_operations.completed.periodic.order(:coverage_started_at)
          .pluck(:coverage_started_at, :coverage_ended_at)
        expect(coverage).to eq([[start_at, end_at]])
        expect(operation.reload).to have_attributes(
          processed_at: Time.current, coverage_started_at: start_at, coverage_ended_at: end_at
        )
        expect(card.billing_operations.where(action_type: "reconcile_advance_coverage")).to be_empty
      end
    end
  end

  shared_examples "arrears in both billing scopes" do
    context "with cycle billing" do
      include_examples "arrears coverage after the rate change"
    end

    context "with segment billing" do
      let(:billing_scope) { "segment" }

      include_examples "arrears coverage after the rate change"
    end
  end

  context "with fixed advance" do
    include_examples "both billing scopes"

    context "when processing continuation with cycle billing" do
      include_examples "fixed advance continuation"
    end

    context "when processing continuation with segment billing" do
      let(:billing_scope) { "segment" }

      include_examples "fixed advance continuation"
    end
  end

  context "with fixed arrears" do
    let(:billing_timing) { "arrears" }
    let(:action_type) { "close_fixed_arrears" }
    let(:initially_completed) { false }

    include_examples "both billing scopes"
    include_examples "arrears in both billing scopes"
  end

  context "with metered arrears" do
    let(:product_type) { "metered" }
    let(:billing_timing) { "arrears" }
    let(:action_type) { "close_metered_arrears" }
    let(:initially_completed) { false }

    include_examples "both billing scopes"
    include_examples "arrears in both billing scopes"
  end

  context "with recurring metered advance" do
    let(:product_type) { "metered" }
    let(:recurring) { true }
    let(:action_type) { "renew_recurring_metered_advance" }

    include_examples "both billing scopes"
  end

  context "with paid fee regrouping" do
    let(:product_type) { "metered" }
    let(:display_on_invoice) { false }
    let(:regroup_paid_fees) { "invoice" }
    let(:action_type) { "regroup_paid_fees" }
    let(:initially_completed) { false }

    include_examples "both billing scopes"
  end
end
