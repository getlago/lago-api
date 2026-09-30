# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Advance graduated pricing across persisted rate segments" do
  subject(:fees) do
    travel_to(Time.zone.parse("2027-01-01 00:05:00")) do
      api_call(perform_jobs: false) do
        post_with_token(organization, "/api/v2/contracts", {contract: {
          external_id: "advance-graduated-contract",
          external_customer_id: customer.external_id,
          plan_code: "graduated-plan",
          started_at: cycle_started_at.iso8601
        }})
      end
    end

    travel_to(first_event_at) do
      # No public endpoint schedules billing segments; keep them processing for event pricing.
      BillingSegments::ScheduleService.call!(customer:)
      create_event({
        external_contract_id: contract.external_id,
        code: billable_metric.code,
        timestamp: first_event_at.utc.strftime("%s.%6N"),
        properties: {"quantity" => 80}
      }, perform_jobs: false)
      # Segment finalization is a separate lifecycle case; it can mark an unused row done.
      perform_all_enqueued_jobs(except: [BillingSegments::ScheduleJob, BillingSegments::ProcessJob])
    end

    if append_second_rate_later
      travel_to(rate_changed_at - 1.day) do
        api_call(perform_jobs: false) do
          post_with_token(organization, "/api/v2/rate_cards/graduated-card/rates", {rate: second_rate_params})
        end
      end
    end

    travel_to(second_event_at) do
      BillingSegments::ScheduleService.call!(customer:)
      create_event({
        external_contract_id: contract.external_id,
        code: billable_metric.code,
        timestamp: second_event_at.utc.strftime("%s.%6N"),
        properties: {"quantity" => 40}
      }, perform_jobs: false)
      perform_all_enqueued_jobs(except: [BillingSegments::ScheduleJob, BillingSegments::ProcessJob])
    end

    if third_event_quantity
      travel_to(Time.zone.parse("2027-01-25 12:00:00")) do
        create_event({
          external_contract_id: contract.external_id,
          code: billable_metric.code,
          properties: {"quantity" => third_event_quantity}
        }, perform_jobs: false)
        perform_all_enqueued_jobs(except: [BillingSegments::ScheduleJob, BillingSegments::ProcessJob])
      end
    end

    Fee.where(contract:, fee_type: :product).order(:created_at).to_a
  end

  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { organization.customers.find_by!(external_id: "graduated-customer") }
  let(:billable_metric) { organization.billable_metrics.find_by!(code: "graduated-usage") }
  let(:contract) { organization.contracts.find_by!(external_id: "advance-graduated-contract") }
  let(:cycle_started_at) { Time.zone.parse("2027-01-01") }
  let(:rate_changed_at) { Time.zone.parse("2027-01-15") }
  let(:cycle_ended_at) { Time.zone.parse("2027-02-01") }
  let(:first_event_at) { Time.zone.parse("2027-01-10 12:00:00") }
  let(:second_event_at) { Time.zone.parse("2027-01-20 12:00:00") }
  let(:first_rate) { organization.rate_cards.find_by!(code: "graduated-card").rates.find_by!(code: "r1") }
  let(:second_rate) { organization.rate_cards.find_by!(code: "graduated-card").rates.find_by!(code: "r2") }
  let(:first_rate_model) { "graduated" }
  let(:append_second_rate_later) { false }
  let(:first_rate_properties) do
    {
      graduated_ranges: [
        {from_value: 0, to_value: 100, per_unit_amount: "1", flat_amount: "0"},
        {from_value: 101, to_value: nil, per_unit_amount: "0.80", flat_amount: "0"}
      ]
    }
  end
  let(:third_event_quantity) { nil }
  let(:second_rate_params) do
    {
      code: "r2", effective_from: rate_changed_at.iso8601, rate_model: "graduated",
      billing_interval_unit: "month", rate_properties: {
        graduated_ranges: [
          {from_value: 0, to_value: 100, per_unit_amount: "2", flat_amount: "0"},
          {from_value: 101, to_value: nil, per_unit_amount: "1.50", flat_amount: "0"}
        ]
      }
    }
  end
  let(:initial_rates) do
    rates = [{
      code: "r1", effective_from: cycle_started_at.iso8601, rate_model: first_rate_model,
      billing_interval_unit: "month", rate_properties: first_rate_properties
    }]
    rates << second_rate_params unless append_second_rate_later
    rates
  end

  around do |example|
    travel_to(Time.zone.parse("2026-12-31 12:00:00"))
    example.run
  ensure
    travel_back
  end

  before do
    create_or_update_customer({external_id: "graduated-customer", name: "Graduated customer", timezone: "UTC", currency: "USD"})
    create_metric({name: "Graduated usage", code: "graduated-usage", aggregation_type: "sum_agg", field_name: "quantity"})

    api_call do
      post_with_token(organization, "/api/v2/products", {product: {
        name: "Graduated usage", code: "graduated-product", product_type: "metered", billable_metric_code: billable_metric.code
      }})
    end

    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: "Advance graduated", code: "graduated-card", product_code: "graduated-product", currency: "USD",
        billing_timing: "advance", proration: false, display_on_invoice: true,
        rates: initial_rates
      }})
    end

    api_call do
      post_with_token(organization, "/api/v2/plans", {plan: {name: "Graduated plan", code: "graduated-plan", currency: "USD"}})
    end

    api_call do
      post_with_token(organization, "/api/v2/plans/graduated-plan/applied_rate_cards", {
        applied_rate_card: {rate_card_code: "graduated-card"}
      })
    end
  end

  it "carries cycle usage into the new tiers without repricing the earlier fee" do
    first_fee, second_fee = fees

    expect([first_fee.amount_cents, second_fee.amount_cents]).to eq([8_000, 7_000])
    expect([first_fee.units, second_fee.units]).to eq([80, 40])
    expect([first_fee.rate_card_rate, second_fee.rate_card_rate]).to eq([first_rate, second_rate])
    expect(first_fee.reload.amount_cents).to eq(8_000)
    expect(BillingSegment.where(contract:).order(:started_at).pluck(:started_at, :cycle_started_at)).to eq([
      [cycle_started_at, cycle_started_at], [rate_changed_at, cycle_started_at]
    ])
    expect(second_fee.properties).to include(
      "from_datetime" => rate_changed_at.iso8601(6),
      "charges_from_datetime" => cycle_started_at.iso8601(6),
      "charges_to_datetime" => BillingSegment.inclusive_end(cycle_ended_at).iso8601(6)
    )
  end

  context "when the first rate is standard and the second is graduated" do
    let(:first_rate_model) { "standard" }
    let(:first_rate_properties) { {amount: "1"} }
    let(:third_event_quantity) { 30 }

    it "carries standard-priced usage into both graduated events without repricing the first fee" do
      first_fee, second_fee, third_fee = fees

      expect([first_fee.amount_cents, second_fee.amount_cents, third_fee.amount_cents]).to eq([8_000, 7_000, 4_500])
      expect([first_fee.units, second_fee.units, third_fee.units]).to eq([80, 40, 30])
      expect([first_fee.rate_card_rate, second_fee.rate_card_rate, third_fee.rate_card_rate]).to eq([
        first_rate, second_rate, second_rate
      ])
      expect(first_fee.reload.amount_cents).to eq(8_000)
      expect([second_fee, third_fee].map { |fee| fee.properties["charges_from_datetime"] }).to eq([
        cycle_started_at.iso8601(6), cycle_started_at.iso8601(6)
      ])
    end
  end

  context "when events arrive on either side of the rate change" do
    let(:first_event_at) { rate_changed_at - Rational(500, 1_000_000) }
    let(:second_event_at) { rate_changed_at }

    it "creates one fee per event with the rate on its side of the microsecond boundary" do
      expect(fees.map { |fee| [fee.rate_card_rate, fee.amount_cents] }).to eq([
        [first_rate, 8_000], [second_rate, 7_000]
      ])
    end
  end

  context "when the new rate is appended after the first segment was stored" do
    let(:append_second_rate_later) { true }

    it "prices the second event with the new rate and shortens its service period without changing the issued fee" do
      first_fee, second_fee = fees

      expect([first_fee.rate_card_rate, second_fee.rate_card_rate]).to eq([first_rate, second_rate])
      expect([first_fee.amount_cents, second_fee.amount_cents]).to eq([8_000, 7_000])
      expect(first_fee.reload.amount_cents).to eq(8_000)
      expect(second_fee.properties).to include(
        "from_datetime" => rate_changed_at.iso8601(6),
        "to_datetime" => BillingSegment.inclusive_end(cycle_ended_at).iso8601(6),
        "charges_from_datetime" => cycle_started_at.iso8601(6)
      )
      expect(BillingSegment.where(contract:).pluck(:rate_card_rate_id, :ended_at)).to eq([
        [first_rate.id, BillingSegment.inclusive_end(cycle_ended_at)]
      ])
    end

    context "when another event arrives before the new rate activates" do
      let(:second_event_at) { rate_changed_at - 12.hours }
      let(:third_event_quantity) { 40 }

      it "shortens the old rate's service period without repricing the earlier fee" do
        first_fee, later_old_rate_fee, new_rate_fee = fees

        expect([first_fee.rate_card_rate, later_old_rate_fee.rate_card_rate, new_rate_fee.rate_card_rate]).to eq([
          first_rate, first_rate, second_rate
        ])
        expect(first_fee.reload.properties["to_datetime"]).to eq(BillingSegment.inclusive_end(cycle_ended_at).iso8601(6))
        expect(later_old_rate_fee.properties).to include(
          "from_datetime" => cycle_started_at.iso8601(6),
          "to_datetime" => BillingSegment.inclusive_end(rate_changed_at).iso8601(6)
        )
        expect(new_rate_fee.properties["from_datetime"]).to eq(rate_changed_at.iso8601(6))
      end
    end
  end
end
