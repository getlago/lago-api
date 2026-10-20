# frozen_string_literal: true

require "rails_helper"

# Terminating on Aug 21 at 22:00 in New York, already Aug 22 in UTC: the termination day is
# served and paid, so the arrears cards close on 21 of August's 31 days in the customer's time,
# and the advance card, paid on Aug 1, owes nothing more.
describe "A contract terminated mid-period is invoiced for the period it served", :premium do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { organization.customers.find_by!(external_id: "terminated-customer") }
  let(:contract) { organization.contracts.find_by!(external_id: "terminated-contract") }
  let(:zone) { Time.find_zone("America/New_York") }
  let(:started_at) { zone.parse("2026-08-01 00:00:00") }
  let(:terminated_at) { zone.parse("2026-08-21 22:00:00") }

  def add_rate_card(code:, product_code:, billing_timing:, amount:)
    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: code, code:, product_code:, currency: "USD", billing_timing:, proration: false,
        rates: [{
          code: "#{code}-rate", effective_from: started_at.iso8601, rate_model: "standard",
          billing_interval_unit: "month", rate_properties: {amount:}
        }]
      }})
    end

    api_call do
      post_with_token(organization, "/api/v2/plans/terminated-plan/applied_rate_cards", {
        applied_rate_card: {rate_card_code: code, units: 1}
      })
    end
  end

  def send_usage(at:, quantity:)
    travel_to(at) do
      create_event({
        external_contract_id: "terminated-contract",
        code: "api-calls",
        timestamp: at.to_f,
        properties: {"quantity" => quantity}
      })
    end
  end

  def fees_by_rate_card(invoice)
    invoice.fees.map { [it.contract_rate_card.rate_card.code, it.amount_cents] }.sort
  end

  around do |example|
    travel_to(started_at - 1.day)
    example.run
  ensure
    travel_back
  end

  before do
    stub_pdf_generation
    create_or_update_customer({external_id: "terminated-customer", timezone: "America/New_York", currency: "USD"})
    create_metric({name: "API calls", code: "api-calls", aggregation_type: "sum_agg", field_name: "quantity"})

    api_call do
      post_with_token(organization, "/api/v2/products", {product: {name: "Platform", code: "platform", product_type: "fixed"}})
    end
    api_call do
      post_with_token(organization, "/api/v2/products", {product: {name: "Support", code: "support", product_type: "fixed"}})
    end
    api_call do
      post_with_token(organization, "/api/v2/products", {product: {
        name: "API calls", code: "api-calls", product_type: "metered", billable_metric_code: "api-calls"
      }})
    end
    api_call do
      post_with_token(organization, "/api/v2/plans", {plan: {name: "Terminated plan", code: "terminated-plan", currency: "USD"}})
    end

    add_rate_card(code: "platform-arrears", product_code: "platform", billing_timing: "arrears", amount: "100")
    add_rate_card(code: "support-advance", product_code: "support", billing_timing: "advance", amount: "15")
    add_rate_card(code: "api-calls-arrears", product_code: "api-calls", billing_timing: "arrears", amount: "0.01")

    travel_to(started_at + 5.minutes) do
      api_call do
        post_with_token(organization, "/api/v2/contracts", {contract: {
          external_id: "terminated-contract",
          external_customer_id: "terminated-customer",
          plan_code: "terminated-plan",
          started_at: started_at.iso8601
        }})
      end
    end

    send_usage(at: zone.parse("2026-08-10 12:00:00"), quantity: 50_000)
    send_usage(at: terminated_at - 1.hour, quantity: 500)

    travel_to(terminated_at) do
      api_call { delete_with_token(organization, "/api/v2/contracts/terminated-contract") }
    end
  end

  it "issues one closing invoice with the arrears slices and the usage up to the termination" do
    opening, closing = Invoice.where(customer:).order(:created_at).to_a

    expect(fees_by_rate_card(opening)).to eq([["support-advance", 1_500]])
    expect(fees_by_rate_card(closing)).to eq([["api-calls-arrears", 50_500], ["platform-arrears", 6_774]])
    expect(closing).to have_attributes(status: "finalized", total_amount_cents: 57_274)
  end

  it "bills nothing for usage or periods after the termination" do
    send_usage(at: terminated_at + 1.hour, quantity: 200)

    travel_to(zone.parse("2026-09-01 00:12:00")) do
      clock_job do
        Clock::CreateBillingSegmentsJob.perform_later
        Clock::ProcessBillingSegmentsJob.perform_later
      end
    end

    expect(Invoice.where(customer:).count).to eq(2)
    expect(contract).to have_attributes(status: "terminated", terminated_at:)
  end
end
