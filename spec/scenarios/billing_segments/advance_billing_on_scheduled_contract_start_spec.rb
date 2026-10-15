# frozen_string_literal: true

require "rails_helper"

# A contract signed for a later date is pending until that date: nothing bills before it,
# and its start activates it and bills a rate card due in advance. Everything between the
# clock and the invoice is real.
describe "A scheduled contract billed in advance invoices when it starts" do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
  let(:product) { create(:product, :fixed, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:rate_card) do
    create(:rate_card, organization:, product:, currency: "EUR", billing_timing: "advance", proration: false)
  end

  let(:contract) { Contract.find_by!(external_id: "contract-scheduled") }

  before do
    stub_pdf_generation

    create(:rate_card_rate, organization:, rate_card:,
      effective_from: Time.zone.parse("2026-01-01 00:00:00"),
      rate_model: "standard", rate_properties: {"amount" => "10"},
      billing_interval_count: 1, billing_interval_unit: "month")

    create(:plan_rate_card, organization:, catalog_plan:, rate_card:, units: 5)

    travel_to(Time.zone.parse("2026-01-10 09:41:00")) do
      perform_enqueued_jobs do
        Contracts::CreateService.call!(
          organization:,
          params: {
            external_customer_id: customer.external_id,
            external_id: "contract-scheduled",
            plan_code: catalog_plan.code,
            started_at: "2026-01-20T00:00:00Z"
          }
        )
      end
    end
  end

  it "bills nothing before the start" do
    travel_to(Time.zone.parse("2026-01-19 23:55:00")) do
      perform_enqueued_jobs do
        Clock::ActivateContractsJob.perform_now
        Clock::CreateBillingSegmentsJob.perform_now
      end
    end

    expect(contract).to be_pending
    expect(Invoice.where(customer:)).to be_empty
  end

  it "activates on its start and invoices the first period" do
    travel_to(Time.zone.parse("2026-01-20 00:05:00")) do
      perform_enqueued_jobs { Clock::ActivateContractsJob.perform_now }
    end

    expect(contract.reload).to be_active
    invoice = Invoice.where(customer:).sole
    expect(invoice).to have_attributes(status: "finalized", total_amount_cents: 5_000)
    expect(BillingSegment.where(customer:).sole).to have_attributes(
      status: "done",
      invoice_id: invoice.id,
      started_at: Time.zone.parse("2026-01-20")
    )
  end

  context "when its start is brought forward to today" do
    it "activates at once and bills from the new start" do
      travel_to(Time.zone.parse("2026-01-15 09:41:00")) do
        perform_enqueued_jobs do
          Contracts::UpdateService.call!(contract:, params: {started_at: "2026-01-15T00:00:00Z"})
        end
      end

      expect(contract.reload).to be_active
      expect(BillingSegment.where(customer:).sole).to have_attributes(started_at: Time.zone.parse("2026-01-15"))
      expect(Invoice.where(customer:).sole.total_amount_cents).to eq(5_000)
    end
  end
end
