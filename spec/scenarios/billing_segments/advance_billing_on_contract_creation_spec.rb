# frozen_string_literal: true

require "rails_helper"

# LAGO-1946: a rate card billed in advance is due the moment the contract starts, so its
# invoice must not wait for the hourly producer. Everything between the create call and the
# invoice is real — the materializer, the calendar, the selection, the writer, the consumer.
describe "A contract billed in advance invoices on creation" do
  subject(:create_contract) do
    Contracts::CreateService.call(
      organization:,
      params: {
        external_customer_id: customer.external_id,
        external_id: "contract-advance",
        plan_code: catalog_plan.code,
        started_at: "2026-01-15T00:00:00Z"
      }
    )
  end

  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
  let(:product) { create(:product, :fixed, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:billing_timing) { "advance" }

  let(:rate_card) do
    create(:rate_card, organization:, product:, currency: "EUR", billing_timing:, proration: false)
  end

  before do
    stub_pdf_generation

    create(:rate_card_rate, organization:, rate_card:,
      effective_from: Time.zone.parse("2026-01-01 00:00:00"),
      rate_model: "standard", rate_properties: {"amount" => "10"},
      billing_interval_count: 1, billing_interval_unit: "month")

    create(:plan_rate_card, organization:, catalog_plan:, rate_card:, units: 5)
  end

  around { |example| travel_to(Time.zone.parse("2026-01-15 09:41:00")) { example.run } }

  it "invoices the first period without waiting for the clock" do
    perform_enqueued_jobs { expect(create_contract).to be_success }

    invoice = Invoice.where(customer:).sole
    expect(invoice).to have_attributes(status: "finalized", currency: "EUR", total_amount_cents: 5_000)
    expect(BillingSegment.where(customer:).sole).to have_attributes(status: "done", invoice_id: invoice.id)
  end

  it "moves the clock on, so the next tick does not bill the period again" do
    perform_enqueued_jobs { create_contract }

    expect { perform_enqueued_jobs { Clock::CreateBillingSegmentsJob.perform_now } }
      .not_to change(BillingSegment, :count)
  end

  # Arrears owes nothing until its first period closes, so the same trigger must produce no
  # invoice at all rather than billing a period that has not happened.
  context "when the rate card bills in arrears" do
    let(:billing_timing) { "arrears" }

    it "invoices nothing yet" do
      perform_enqueued_jobs { expect(create_contract).to be_success }

      expect(Invoice.where(customer:)).to be_empty
      expect(BillingSegment.where(customer:)).to be_empty
    end
  end
end
