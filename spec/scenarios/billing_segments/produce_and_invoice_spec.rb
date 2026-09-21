# frozen_string_literal: true

require "rails_helper"

# The two halves meeting: the hourly clock produces a customer's due segments, and the
# consumer already on main turns them into an invoice. Everything between is real —
# the calendar, the selection, the writer, the clock, the fee computation.
describe "Billing segments produced by the clock and invoiced" do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
  let(:product) { create(:product, :fixed, organization:) }

  let(:rate_card) do
    create(:rate_card, organization:, product:, currency: "EUR", billing_timing: "arrears", proration: false)
  end

  let(:contract) do
    create(:contract, organization:, customer:, billing_entity: organization.default_billing_entity,
      started_at: Time.zone.parse("2026-01-01 00:00:00"))
  end

  before do
    stub_pdf_generation

    create(:rate_card_rate, organization:, rate_card:,
      effective_from: Time.zone.parse("2026-01-01 00:00:00"),
      rate_model: "standard", rate_properties: {"amount" => "50"},
      billing_interval_count: 1, billing_interval_unit: "month")

    create(:contract_rate_card, organization:, contract:, rate_card:, units: 3,
      effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1),
      next_billing_at: Time.zone.parse("2026-02-01 00:00:00"))
  end

  it "bills January in arrears on the tick that follows it" do
    travel_to(Time.zone.parse("2026-02-01 00:12:00")) do
      perform_enqueued_jobs { Clock::CreateBillingSegmentsJob.perform_now }
    end

    segment = BillingSegment.find_by(customer:)
    expect(segment).to have_attributes(
      started_at: Time.zone.parse("2026-01-01 00:00:00"),
      ended_at: BillingSegment.inclusive_end(Time.zone.parse("2026-02-01 00:00:00")),
      billing_at: Time.zone.parse("2026-02-01 00:00:00"),
      currency: "EUR",
      status: "pending"
    )

    invoice = BillingSegments::ProcessService.call!(customer:).invoices.sole.reload

    expect(invoice).to have_attributes(status: "finalized", currency: "EUR", total_amount_cents: 15_000)
    expect(segment.reload).to have_attributes(status: "done", invoice_id: invoice.id)
  end

  it "moves the clock on, so the next tick bills February and not January again" do
    travel_to(Time.zone.parse("2026-02-01 00:12:00")) do
      perform_enqueued_jobs { Clock::CreateBillingSegmentsJob.perform_now }
    end

    expect(ContractRateCard.sole.next_billing_at).to eq(Time.zone.parse("2026-03-01 00:00:00"))

    travel_to(Time.zone.parse("2026-03-01 00:12:00")) do
      perform_enqueued_jobs { Clock::CreateBillingSegmentsJob.perform_now }
    end

    expect(BillingSegment.where(customer:).order(:started_at).pluck(:started_at)).to eq(
      [Time.zone.parse("2026-01-01 00:00:00"), Time.zone.parse("2026-02-01 00:00:00")]
    )
  end
end
