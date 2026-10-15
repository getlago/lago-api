# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Advance graduated usage before the first priced segment" do
  subject(:fees) do
    travel_to(cycle_started_at + 5.minutes) do
      api_call(perform_jobs: false) do
        post_with_token(organization, "/api/v2/contracts", {contract: {
          external_id: "unpriced-contract", external_customer_id: customer.external_id,
          plan_code: "unpriced-plan", started_at: cycle_started_at.iso8601
        }})
      end
    end

    event_quantities.each do |timestamp, quantity|
      travel_to(timestamp) do
        BillingSegments::ScheduleService.call!(customer:)
        create_event({
          external_contract_id: contract.external_id, code: billable_metric.code,
          timestamp: timestamp.utc.strftime("%s.%6N"), properties: {"quantity" => quantity}
        }, perform_jobs: false)
        perform_all_enqueued_jobs(except: [BillingSegments::ScheduleJob, BillingSegments::ProcessJob])
      end
    end

    Fee.where(contract:, fee_type: :product).order(:created_at).to_a
  end

  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { organization.customers.find_by!(external_id: "unpriced-customer") }
  let(:billable_metric) { organization.billable_metrics.find_by!(code: "unpriced-usage") }
  let(:contract) { organization.contracts.find_by!(external_id: "unpriced-contract") }
  let(:rate) { organization.rate_cards.find_by!(code: "unpriced-card").rates.sole }
  let(:cycle_started_at) { Time.zone.parse("2027-01-01") }
  let(:rate_started_at) { Time.zone.parse("2027-01-15") }
  let(:early_event_at) { Time.zone.parse("2027-01-05 12:00:00") }
  let(:priced_event_at) { Time.zone.parse("2027-01-20 12:00:00") }
  let(:event_quantities) { [[early_event_at, 100], [priced_event_at, 40]] }

  around do |example|
    travel_to(Time.zone.parse("2026-12-31 12:00:00"))
    example.run
  ensure
    travel_back
  end

  before do
    create_or_update_customer({external_id: "unpriced-customer", timezone: "UTC", currency: "USD"})
    create_metric({name: "Unpriced usage", code: "unpriced-usage", aggregation_type: "sum_agg", field_name: "quantity"})

    api_call do
      post_with_token(organization, "/api/v2/products", {product: {
        name: "Unpriced usage", code: "unpriced-product", product_type: "metered", billable_metric_code: billable_metric.code
      }})
    end

    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: "Delayed graduated rate", code: "unpriced-card", product_code: "unpriced-product", currency: "USD",
        billing_timing: "advance", proration: false, display_on_invoice: true,
        rates: [{
          code: "r1", effective_from: rate_started_at.iso8601, rate_model: "graduated",
          billing_interval_unit: "month", rate_properties: {
            graduated_ranges: [
              {to_value: "100", per_unit_amount: "1", flat_amount: "0"},
              {to_value: nil, per_unit_amount: "0.80", flat_amount: "0"}
            ]
          }
        }]
      }})
    end

    api_call do
      post_with_token(organization, "/api/v2/plans", {plan: {name: "Unpriced plan", code: "unpriced-plan", currency: "USD"}})
    end

    api_call do
      post_with_token(organization, "/api/v2/plans/unpriced-plan/applied_rate_cards", {
        applied_rate_card: {rate_card_code: "unpriced-card"}
      })
    end
  end

  it "excludes unpriced usage and bills the 40 priced units at the first tier" do
    fee = fees.sole

    expect(Event.where(organization:, external_subscription_id: contract.external_id).order(:timestamp).pluck(:timestamp))
      .to eq([early_event_at, priced_event_at])
    expect(fee).to have_attributes(amount_cents: 4_000, units: 40, rate_card_rate: rate)
    expect(fee.pay_in_advance_event_id).to eq(Event.find_by!(organization:, timestamp: priced_event_at).id)
    expect(fee.properties).to include(
      "from_datetime" => rate_started_at.iso8601(6),
      "charges_from_datetime" => rate_started_at.iso8601(6)
    )
  end

  context "without usage before the rate starts" do
    let(:event_quantities) { [[priced_event_at, 40]] }

    it "prices the same 40 units at the first tier" do
      expect(fees.sole).to have_attributes(amount_cents: 4_000, units: 40, rate_card_rate: rate)
    end
  end
end
