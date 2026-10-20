# frozen_string_literal: true

require "rails_helper"

# Voiding a contract invoice does not reopen its period: the segments stay done on the voided
# invoice, so the next tick bills the next period only. Billing a voided period again is the
# regenerate flow's job.
describe "Void a contract invoice" do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { organization.customers.find_by!(external_id: "void-customer") }
  let(:contract) { organization.contracts.find_by!(external_id: "void-contract") }
  let(:rate) { organization.rate_cards.find_by!(code: "void-card").rates.sole }
  let(:january) { Time.zone.parse("2027-01-01") }
  let(:february) { Time.zone.parse("2027-02-01") }

  around do |example|
    travel_to(Time.zone.parse("2026-12-31 12:00:00"))
    example.run
  ensure
    travel_back
  end

  before do
    stub_pdf_generation
    create_or_update_customer({external_id: "void-customer", timezone: "UTC", currency: "USD"})
    create_metric({name: "Void usage", code: "void-usage", aggregation_type: "sum_agg", field_name: "quantity"})

    api_call do
      post_with_token(organization, "/api/v2/products", {product: {
        name: "Void usage", code: "void-product", product_type: "metered", billable_metric_code: "void-usage"
      }})
    end

    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: "Void", code: "void-card", product_code: "void-product", currency: "USD",
        billing_timing: "arrears", proration: false, display_on_invoice: true,
        rates: [{code: "r1", effective_from: january.iso8601, rate_model: "standard",
                 billing_interval_unit: "month", rate_properties: {amount: "1"}}]
      }})
    end

    api_call do
      post_with_token(organization, "/api/v2/plans", {plan: {name: "Void plan", code: "void-plan", currency: "USD"}})
    end

    api_call do
      post_with_token(organization, "/api/v2/plans/void-plan/applied_rate_cards", {
        applied_rate_card: {rate_card_code: "void-card"}
      })
    end

    travel_to(january + 5.minutes) do
      api_call do
        post_with_token(organization, "/api/v2/contracts", {contract: {
          external_id: "void-contract", external_customer_id: "void-customer",
          plan_code: "void-plan", started_at: january.iso8601
        }})
      end
    end

    event_at = Time.zone.parse("2027-01-10 12:00:00")
    travel_to(event_at) do
      create_event({external_contract_id: "void-contract", code: "void-usage",
                    timestamp: event_at.to_i, properties: {"quantity" => 80}})
    end

    tick(february + 12.minutes)
  end

  def tick(at)
    travel_to(at) do
      Clock::CreateBillingSegmentsJob.perform_now
      perform_all_enqueued_jobs
    end
  end

  def void_contract_invoice(invoice, params = {})
    api_call { post_with_token(organization, "/api/v2/invoices/#{invoice.id}/void", params) }
    invoice.reload
  end

  it "keeps the period billed by the voided invoice, with its fees and their rate" do
    invoice = customer.invoices.sole
    fee = invoice.fees.sole
    expect(fee).to have_attributes(rate_card_rate_id: rate.id, units: 80, amount_cents: 8_000)

    travel_to(february + 1.day) { void_contract_invoice(invoice) }

    expect(invoice).to be_voided
    expect(fee.reload).to have_attributes(invoice_id: invoice.id, rate_card_rate_id: rate.id, units: 80, amount_cents: 8_000)
    expect(BillingSegment.where(contract:).sole).to have_attributes(started_at: january, status: "done", invoice_id: invoice.id)

    tick(Time.zone.parse("2027-03-01 00:12:00"))

    expect(BillingSegment.where(contract:).order(:started_at).pluck(:started_at)).to eq([january, february])
    expect(Fee.where(contract:).where("properties->>'charges_from_datetime' = ?", fee.properties["charges_from_datetime"]))
      .to eq([fee])
  end

  it "sends the invoice.voided webhook with the product fees" do
    invoice = customer.invoices.sole
    create(:webhook_endpoint, organization:, webhook_url: "https://hooks.example.com/lago")
    stub_request(:post, "https://hooks.example.com/lago").to_return(status: 200)

    travel_to(february + 1.day) { void_contract_invoice(invoice) }

    payload = organization.webhooks.where(webhook_type: "invoice.voided").sole.payload
    expect(payload.dig("invoice", "lago_id")).to eq(invoice.id)
    expect(payload.dig("invoice", "status")).to eq("voided")
    expect(payload.dig("invoice", "fees").pluck("lago_id")).to eq([invoice.fees.sole.id])
  end

  context "with a credit note for the voided amount", :premium do
    it "credits the product fees" do
      invoice = customer.invoices.sole

      travel_to(february + 1.day) do
        void_contract_invoice(invoice, {generate_credit_note: true, credit_amount: 8_000, refund_amount: 0})
      end

      expect(invoice).to be_voided
      expect(invoice.credit_notes.sole).to have_attributes(credit_amount_cents: 8_000, credit_status: "available")
      expect(invoice.credit_notes.sole.items.sole.fee).to eq(invoice.fees.sole)
    end
  end
end
