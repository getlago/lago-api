# frozen_string_literal: true

require "rails_helper"

# The clocks discover due operations and invoice them through the real calendar and fee computation.
describe "Billing operations discovered by the clocks and invoiced" do
  let(:organization) { create(:organization, webhook_url: nil, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
  let(:product) { create(:product, :fixed, organization:) }

  let(:rate_card) do
    create(:rate_card, organization:, product:, currency: "EUR", billing_timing: "arrears", proration: false)
  end

  let(:contract) do
    create(:contract, :pending, organization:, customer:, billing_entity: organization.default_billing_entity,
      started_at: Time.zone.parse("2026-01-01 00:00:00"))
  end

  before do
    stub_pdf_generation

    create(:rate_card_rate, organization:, rate_card:,
      effective_from: Time.zone.parse("2026-01-01 00:00:00"),
      rate_model: "standard", rate_properties: {"amount" => "50"},
      billing_interval_count: 1, billing_interval_unit: "month")

    create(:contract_rate_card, organization:, contract:, rate_card:, units: 3,
      effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1))

    travel_to(Time.zone.parse("2026-01-01 00:05:00")) do
      perform_enqueued_jobs { Clock::ActivateContractsJob.perform_now }
    end
  end

  def run_billing_clocks
    perform_enqueued_jobs do
      Clock::ScheduleBillingOperationsJob.perform_now
    end
  end

  it "bills January in arrears on the tick that follows it" do
    travel_to(Time.zone.parse("2026-02-01 00:12:00")) do
      run_billing_clocks
    end

    invoice = Invoice.where(customer:).sole

    expect(invoice).to have_attributes(status: "finalized", currency: "EUR", total_amount_cents: 15_000)
    expect(invoice.billing_operations.sole).to have_attributes(
      target_cycle_started_at: Time.zone.parse("2026-01-01 00:00:00"),
      billing_at: Time.zone.parse("2026-02-01 00:00:00"),
      processed_at: Time.zone.parse("2026-02-01 00:12:00"),
      invoice_id: invoice.id
    )
    expect(LegacyBillingSegment.where(customer_id: customer.id)).to be_empty
  end

  it "moves the clock on, so the next tick bills February and not January again" do
    travel_to(Time.zone.parse("2026-02-01 00:12:00")) do
      run_billing_clocks
    end

    expect(ContractRateCard.sole.next_billing_at).to eq(Time.zone.parse("2026-03-01 00:00:00"))

    travel_to(Time.zone.parse("2026-03-01 00:12:00")) do
      run_billing_clocks
    end

    expect(BillingOperation.where(customer:).where.not(processed_at: nil)
      .order(:target_cycle_started_at).pluck(:target_cycle_started_at)).to eq(
      [Time.zone.parse("2026-01-01 00:00:00"), Time.zone.parse("2026-02-01 00:00:00")]
    )
  end
end
