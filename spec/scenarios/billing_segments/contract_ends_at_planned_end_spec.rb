# frozen_string_literal: true

require "rails_helper"

# A contract created with an end terminates on its own once the end passes, through the same
# close-out as a manual termination: Aug 21 at 14:00 in Tokyo bills 21 of August's 31 days.
describe "A contract terminates at its planned end", :premium do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { organization.customers.find_by!(external_id: "ending-customer") }
  let(:contract) { organization.contracts.find_by!(external_id: "ending-contract") }
  let(:zone) { Time.find_zone("Asia/Tokyo") }
  let(:started_at) { zone.parse("2026-08-01 00:00:00") }
  let(:ended_at) { zone.parse("2026-08-21 14:00:00") }

  around do |example|
    travel_to(started_at - 1.day)
    example.run
  ensure
    travel_back
  end

  before do
    stub_pdf_generation
    create_or_update_customer({external_id: "ending-customer", timezone: "Asia/Tokyo", currency: "USD"})

    api_call do
      post_with_token(organization, "/api/v2/products", {product: {name: "Platform", code: "platform", product_type: "fixed"}})
    end
    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: "Platform", code: "platform-arrears", product_code: "platform", currency: "USD",
        billing_timing: "arrears", proration: false,
        rates: [{
          code: "platform-rate", effective_from: started_at.iso8601, rate_model: "standard",
          billing_interval_unit: "month", rate_properties: {amount: "100"}
        }]
      }})
    end
    api_call do
      post_with_token(organization, "/api/v2/plans", {plan: {name: "Ending plan", code: "ending-plan", currency: "USD"}})
    end
    api_call do
      post_with_token(organization, "/api/v2/plans/ending-plan/applied_rate_cards", {
        applied_rate_card: {rate_card_code: "platform-arrears", units: 1}
      })
    end

    travel_to(started_at + 5.minutes) do
      api_call do
        post_with_token(organization, "/api/v2/contracts", {contract: {
          external_id: "ending-contract", external_customer_id: "ending-customer", plan_code: "ending-plan",
          started_at: started_at.iso8601, ended_at: ended_at.iso8601
        }})
      end
    end

    travel_to(ended_at + 5.minutes) do
      clock_job do
        Clock::TerminateEndedContractsJob.perform_later
        Clock::CreateBillingSegmentsJob.perform_later
        Clock::ProcessBillingSegmentsJob.perform_later
      end
    end
  end

  it "terminates at the end and bills the days served" do
    expect(contract).to have_attributes(status: "terminated", terminated_at: ended_at)
    expect(Invoice.where(customer:).sole.total_amount_cents).to eq(6_774)
  end

  context "when the end falls on a period boundary" do
    let(:ended_at) { zone.parse("2026-09-01 00:00:00") }

    it "bills the whole period, with no partial slice" do
      expect(contract).to have_attributes(status: "terminated", terminated_at: ended_at)
      expect(Invoice.where(customer:).sole.total_amount_cents).to eq(10_000)
    end
  end
end
