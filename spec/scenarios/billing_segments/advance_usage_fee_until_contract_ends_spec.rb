# frozen_string_literal: true

require "rails_helper"

RSpec.describe "An advance usage fee waits for the end of its contract period" do
  subject(:billing_timeline) do
    travel_to(period_started_at + 5.minutes) do
      api_call(perform_jobs: false) do
        post_with_token(organization, "/api/v2/contracts", {contract: {
          external_id: "advance-period-contract",
          external_customer_id: customer.external_id,
          plan_code: "advance-period-plan",
          started_at: period_started_at.iso8601
        }})
      end
      perform_all_enqueued_jobs(except: [BillingSegments::ScheduleJob, BillingSegments::ProcessJob])
      perform_enqueued_jobs { BillingSegments::ScheduleJob.perform_now(customer.id) }
    end

    travel_to(event_at) do
      create_event({
        external_contract_id: contract.external_id,
        code: billable_metric.code,
        timestamp: event_at.utc.strftime("%s.%6N"),
        properties: {"quantity" => 40}
      }, perform_jobs: false)
      perform_all_enqueued_jobs(except: [BillingSegments::ScheduleJob, BillingSegments::ProcessJob])
      Fees::UpdateService.call!(
        fee: Fee.find_by!(contract:, fee_type: :product),
        params: {payment_status: "succeeded"}
      )
    end

    active_period = {
      fee: Fee.find_by!(contract:, fee_type: :product),
      segment: BillingSegment.where(customer:).sole,
      invoices: Invoice.where(customer:).to_a
    }

    travel_to(period_ended_at + 5.minutes) do
      delete_with_token(organization, "/api/v2/contracts/#{contract.external_id}")
      perform_all_enqueued_jobs(except: [BillingSegments::ScheduleJob, BillingSegments::ProcessJob])
      perform_enqueued_jobs { BillingSegments::ScheduleJob.perform_now(customer.id) }
    end

    segment = BillingSegment.where(customer:).sole
    {active_period:, segment:, invoice: segment.invoice}
  end

  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { organization.customers.find_by!(external_id: "advance-period-customer") }
  let(:contract) { organization.contracts.find_by!(external_id: "advance-period-contract") }
  let(:billable_metric) { organization.billable_metrics.find_by!(code: "advance-period-usage") }
  let(:period_started_at) { Time.zone.parse("2027-01-01 00:00:00") }
  let(:period_ended_at) { Time.zone.parse("2027-02-01 00:00:00") }
  let(:event_at) { Time.zone.parse("2027-01-15 12:00:00") }
  let(:invoice) { billing_timeline.fetch(:invoice) }

  around do |example|
    travel_to(Time.zone.parse("2026-12-31 12:00:00"))
    example.run
  ensure
    travel_back
  end

  before do
    stub_pdf_generation
    create_or_update_customer({external_id: "advance-period-customer", timezone: "UTC", currency: "USD"})
    create_metric({name: "Advance period usage", code: "advance-period-usage", aggregation_type: "sum_agg",
                   field_name: "quantity"})

    api_call do
      post_with_token(organization, "/api/v2/products", {product: {
        name: "Advance period usage", code: "advance-period-product", product_type: "metered",
        billable_metric_code: billable_metric.code
      }})
    end

    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: "Advance period card", code: "advance-period-card", product_code: "advance-period-product",
        currency: "USD", billing_timing: "advance", proration: false, display_on_invoice: false,
        regroup_paid_fees: "invoice",
        rates: [{
          code: "advance-period-rate", effective_from: period_started_at.iso8601, rate_model: "standard",
          billing_interval_unit: "month", rate_properties: {amount: "1"}
        }]
      }})
    end

    api_call do
      post_with_token(organization, "/api/v2/plans", {plan: {
        name: "Advance period plan", code: "advance-period-plan", currency: "USD"
      }})
    end

    api_call do
      post_with_token(organization, "/api/v2/plans/advance-period-plan/applied_rate_cards", {
        applied_rate_card: {rate_card_code: "advance-period-card"}
      })
    end
  end

  it "invoices the metered fee only when the ended first period is processed" do
    timeline = billing_timeline

    expect(timeline.fetch(:active_period).fetch(:fee)).to have_attributes(
      amount_cents: 4_000, units: 40, pay_in_advance: true, payment_status: "succeeded", invoice_id: nil
    )
    expect(timeline.fetch(:active_period).fetch(:segment)).to have_attributes(status: "pending", invoice_id: nil)
    expect(timeline.fetch(:active_period).fetch(:invoices)).to be_empty
    expect(timeline.fetch(:segment)).to have_attributes(status: "done", invoice_id: invoice.id)
    expect(invoice).to have_attributes(status: "finalized", total_amount_cents: 4_000)
    expect(invoice.created_at).to be > period_ended_at
    expect(Fee.find_by!(contract:, fee_type: :product).invoice_id).to eq(invoice.id)
  end
end
