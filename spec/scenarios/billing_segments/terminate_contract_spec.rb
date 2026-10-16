# frozen_string_literal: true

require "rails_helper"

# Terminating a contract closes every card at that instant. The arrears card bills the days
# it served, the termination day included; the advance card was paid for the cycle when it
# opened and bills nothing more. Neither card prorates, which a cut-short last cycle overrides.
describe "Terminate a contract", :premium do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { organization.customers.find_by!(external_id: "terminate-customer") }
  let(:contract) { organization.contracts.find_by!(external_id: "terminate-contract") }
  let(:timezone) { Time.find_zone("Asia/Tokyo") }
  let(:august) { timezone.parse("2026-08-01 00:00:00") }
  let(:terminated_at) { timezone.parse("2026-08-21 14:00:00") }

  around do |example|
    travel_to(timezone.parse("2026-07-31 12:00:00"))
    example.run
  ensure
    travel_back
  end

  before do
    stub_pdf_generation
    create_or_update_customer({external_id: "terminate-customer", timezone: timezone.name, currency: "USD"})

    create_fixed_rate_card(code: "platform", billing_timing: "arrears", amount: "100")
    create_fixed_rate_card(code: "support", billing_timing: "advance", amount: "15")

    api_call do
      post_with_token(organization, "/api/v2/plans", {plan: {name: "Terminate plan", code: "terminate-plan", currency: "USD"}})
    end

    %w[platform support].each do |code|
      api_call do
        post_with_token(organization, "/api/v2/plans/terminate-plan/applied_rate_cards", {
          applied_rate_card: {rate_card_code: code, units: 1}
        })
      end
    end

    travel_to(august + 5.minutes) do
      api_call do
        post_with_token(organization, "/api/v2/contracts", {contract: {
          external_id: "terminate-contract", external_customer_id: "terminate-customer",
          plan_code: "terminate-plan", started_at: august.iso8601
        }})
      end
    end
  end

  def create_fixed_rate_card(code:, billing_timing:, amount:)
    api_call do
      post_with_token(organization, "/api/v2/products", {product: {name: code, code:, product_type: "fixed"}})
    end

    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: code, code:, product_code: code, currency: "USD",
        billing_timing:, proration: false, display_on_invoice: true,
        rates: [{code: "#{code}-rate", effective_from: august.iso8601, rate_model: "standard",
                 billing_interval_unit: "month", rate_properties: {amount:}}]
      }})
    end
  end

  def terminate
    travel_to(terminated_at) do
      api_call { delete_with_token(organization, "/api/v2/contracts/terminate-contract") }
    end
  end

  it "invoices the arrears card's served days and nothing for the paid advance cycle" do
    advance_invoice = customer.invoices.sole
    expect(advance_invoice.total_amount_cents).to eq(1_500)

    terminate

    expect(contract).to have_attributes(status: "terminated", terminated_at:, ended_at: terminated_at)

    closing_invoice = customer.invoices.where.not(id: advance_invoice.id).sole
    # 21 of August's 31 days of the $100 platform card.
    expect(closing_invoice).to have_attributes(status: "finalized", total_amount_cents: 6_774)
    expect(closing_invoice.fees.sole.contract_rate_card.rate_card.code).to eq("platform")
  end

  it "bills nothing on the ticks that follow" do
    terminate

    expect do
      travel_to(timezone.parse("2026-09-01 00:12:00")) do
        Clock::CreateBillingSegmentsJob.perform_now
        perform_all_enqueued_jobs
      end
    end.not_to change { customer.invoices.count }

    expect(contract.applied_rate_cards.pluck(:next_billing_at)).to eq([nil, nil])
  end
end
