# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Graduated flat fees and filter buckets across a rate change" do
  subject(:fees) do
    travel_to(cycle_started_at + 5.minutes) do
      api_call(perform_jobs: false) do
        post_with_token(organization, "/api/v2/contracts", {contract: {
          external_id: "flat-reset-contract", external_customer_id: customer.external_id,
          code: "default",
          plan_code: "flat-reset-plan", started_at: cycle_started_at.iso8601
        }})
      end
    end

    timeline = event_properties
    if billing_timing == "arrears"
      timeline += [[rate_changed_at, nil], [cycle_ended_at, nil]]
    end

    timeline.sort_by(&:first).each do |timestamp, properties|
      travel_to(timestamp) do
        if properties
          create_event({
            external_contract_id: contract.external_id, code: billable_metric.code,
            timestamp: timestamp.utc.strftime("%s.%6N"), properties:
          }, perform_jobs: false)
          perform_all_enqueued_jobs(except: [BillingOperations::ProcessJob])
        else
          BillingOperations::ScheduleJob.perform_now(customer.id)
          perform_all_enqueued_jobs(only: [BillingOperations::ProcessJob])
        end
      end
    end

    Fee.where(contract:, fee_type: :product).order(:created_at).sort_by { |fee| fee.properties.fetch("from_datetime") }
  end

  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { organization.customers.find_by!(external_id: "flat-reset-customer") }
  let(:billable_metric) { organization.billable_metrics.find_by!(code: "flat-reset-usage") }
  let(:contract) { organization.contracts.find_by!(external_id: "flat-reset-contract") }
  let(:rate_card) { organization.rate_cards.find_by!(code: "flat-reset-card") }
  let(:first_rate) { rate_card.rates.find_by!(code: "r1") }
  let(:second_rate) { rate_card.rates.find_by!(code: "r2") }
  let(:cycle_started_at) { Time.zone.parse("2027-01-01") }
  let(:first_rate_at) { cycle_started_at }
  let(:cycle_ended_at) { Time.zone.parse("2027-02-01") }
  let(:rate_changed_at) { Time.zone.parse("2027-01-15") }
  let(:first_event_at) { Time.zone.parse("2027-01-10 12:00:00") }
  let(:second_event_at) { Time.zone.parse("2027-01-20 12:00:00") }
  let(:billing_timing) { "advance" }
  let(:flat_amount) { "50" }
  let(:first_model) { "standard" }
  let(:first_properties) { {amount: "1"} }
  let(:second_model) { "graduated" }
  let(:additional_rates) { [] }
  let(:second_properties) do
    {graduated_ranges: [
      {to_value: "100", per_unit_amount: "2", flat_amount:},
      {to_value: nil, per_unit_amount: "1.50", flat_amount: "0"}
    ]}
  end
  let(:metric_filters) { [] }
  let(:metric_rounding) { {} }
  let(:product_filter_code) { nil }
  let(:first_event_properties) { {"quantity" => 80} }
  let(:second_event_properties) { {"quantity" => 40} }
  let(:event_properties) { [[first_event_at, first_event_properties], [second_event_at, second_event_properties]] }

  around do |example|
    travel_to(Time.zone.parse("2026-12-31 12:00:00"))
    example.run
  ensure
    travel_back
  end

  before do
    stub_pdf_generation
    create_or_update_customer({external_id: "flat-reset-customer", timezone: "UTC", currency: "USD"})
    create_metric({name: "Flat reset usage", code: "flat-reset-usage", aggregation_type: "sum_agg",
                  field_name: "quantity", filters: metric_filters, **metric_rounding})

    api_call do
      post_with_token(organization, "/api/v2/products", {product: {
        name: "Flat reset usage", code: "flat-reset-product", product_type: "metered", billable_metric_code: billable_metric.code
      }})
    end

    if metric_filters.any?
      api_call do
        post_with_token(organization, "/api/v2/products/flat-reset-product/filters", {filter: {
          name: "US", code: "us", values: [{key: "region", value: "us"}]
        }})
      end
    end

    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: "Flat reset", code: "flat-reset-card", product_code: "flat-reset-product", currency: "USD",
        billing_timing:, proration: false, display_on_invoice: true, product_filter_code:,
        rates: [
          {code: "r1", effective_from: first_rate_at.iso8601, rate_model: first_model,
           billing_interval_unit: "month", rate_properties: first_properties},
          {code: "r2", effective_from: rate_changed_at.iso8601, rate_model: second_model,
           billing_interval_unit: "month", rate_properties: second_properties}
        ] + additional_rates
      }})
    end

    api_call do
      post_with_token(organization, "/api/v2/plans", {plan: {name: "Flat reset plan", code: "flat-reset-plan", currency: "USD"}})
    end

    api_call do
      post_with_token(organization, "/api/v2/plans/flat-reset-plan/applied_rate_cards", {
        applied_rate_card: {rate_card_code: "flat-reset-card"}
      })
    end
  end

  it "resets tiers at the rate change and immediately invoices the new event with its flat amount" do
    # The new segment starts at zero: 40 first-tier units × $2 + $50 flat.
    expect(fees.map { |fee| [fee.rate_card_rate, fee.units, fee.amount_cents] }).to eq([
      [first_rate, 80, 8_000], [second_rate, 40, 13_000]
    ])
    expect(fees.last.properties["charges_from_datetime"]).to eq(rate_changed_at.iso8601(6))
    expect(fees.first.reload.amount_cents).to eq(8_000)
    expect(fees.map { |fee| fee.invoice.created_at }).to eq([first_event_at, second_event_at])
  end

  context "without a flat amount" do
    let(:flat_amount) { "0" }

    it "resets tiers while charging only the per-unit amounts" do
      expect(fees.map(&:amount_cents)).to eq([8_000, 8_000])
    end
  end

  context "when another event arrives under the graduated rate" do
    let(:third_event_quantity) { 30 }
    let(:event_properties) do
      super() + [[Time.zone.parse("2027-01-25 12:00:00"), {"quantity" => third_event_quantity}]]
    end

    it "charges the flat amount once and keeps both new events in the first tier" do
      expect(fees.map { |fee| [fee.rate_card_rate, fee.units, fee.amount_cents] }).to eq([
        [first_rate, 80, 8_000], [second_rate, 40, 13_000], [second_rate, 30, 6_000]
      ])
    end

    context "when the new segment's own usage crosses the tier" do
      let(:third_event_quantity) { 80 }

      it "accumulates within the segment without charging the first-tier flat amount again" do
        expect(fees.map(&:amount_cents)).to eq([8_000, 13_000, 15_000])
      end
    end
  end

  context "without earlier standard usage" do
    let(:event_properties) { [[second_event_at, second_event_properties]] }

    it "charges the flat amount on the first graduated event" do
      expect(fees.sole).to have_attributes(rate_card_rate: second_rate, units: 40, amount_cents: 13_000)
    end
  end

  context "with arrears billing" do
    let(:billing_timing) { "arrears" }

    it "prices the new segment from the cycle's opening usage without rebilling earlier units" do
      expect(fees.map { |fee| [fee.rate_card_rate, fee.units, fee.amount_cents] }).to eq([
        [first_rate, 80, 8_000], [second_rate, 40, 12_000] # 20 × $2 + $50 flat + 20 × $1.50
      ])
      expect(fees.last.properties["from_datetime"]).to eq(rate_changed_at.iso8601(6))
      expect(fees.last.properties["charges_from_datetime"]).to eq(rate_changed_at.iso8601(6))
      expect(fees.map { |fee| fee.invoice.created_at }).to eq([cycle_ended_at, cycle_ended_at])
      expect(fees.map(&:invoice_id).uniq).to eq([fees.first.invoice_id])
    end

    context "when only the prices change" do
      let(:first_model) { "graduated" }
      let(:first_properties) { {graduated_ranges: [{to_value: nil, per_unit_amount: "1", flat_amount: "0"}]} }

      it "carries tier position and charges the new rate's own flat amount" do
        expect(fees.map(&:amount_cents)).to eq([8_000, 12_000]) # R2: 20 × $2 + $50 flat + 20 × $1.50.
      end
    end

    context "when the metric floors each segment's sum to whole units" do
      let(:metric_rounding) { {rounding_function: "floor", rounding_precision: 0} }
      let(:event_properties) do
        [[first_event_at, {"quantity" => "39.7"}], [first_event_at + 1.minute, {"quantity" => "40.7"}],
          [rate_changed_at, {"quantity" => "20.7"}]]
      end

      it "bills all 20 graduated units in the first tier" do
        # floor(39.7 + 40.7) = 80, leaving exactly 20 first-tier units for the new rate.
        expect(fees.map { |fee| [fee.units, fee.amount_cents] }).to eq([[80, 80 * 100], [20, 20 * 200 + 5_000]])
      end

      context "when the new rate uses volume tiers" do
        let(:second_model) { "volume" }
        let(:second_properties) do
          {volume_ranges: [
            {to_value: "100", per_unit_amount: "2", flat_amount: "0"},
            {to_value: nil, per_unit_amount: "1", flat_amount: "0"}
          ]}
        end

        it "selects the volume tier at 100 rounded units and bills only the new segment's 20" do
          expect(fees.map { |fee| [fee.units, fee.amount_cents] }).to eq([[80, 80 * 100], [20, 20 * 200]])
        end
      end
    end

    context "when the cycle starts before its first rate" do
      let(:first_rate_at) { Time.utc(2027, 1, 5) }
      let(:event_properties) do
        [[first_rate_at - 1.second, {"quantity" => 200}], [first_rate_at, {"quantity" => 80}], [rate_changed_at, {"quantity" => 40}]]
      end

      it "bills one operation from the first priced instant and carries only its usage across the switch" do
        expect(fees.map { |fee| [fee.rate_card_rate, fee.events_count, fee.units, fee.amount_cents] }).to eq([
          [first_rate, 1, 80, 8_000], [second_rate, 1, 40, 12_000] # R2: 20 × $2 + $50 + 20 × $1.50.
        ])
        invoice = fees.map(&:invoice).uniq.sole
        expect(invoice.created_at).to eq(cycle_ended_at)
        expect(invoice.billing_operations.sole).to have_attributes(target_cycle_started_at: cycle_started_at,
          coverage_started_at: first_rate_at, coverage_ended_at: cycle_ended_at)
      end
    end

    context "when the rates group by the same event property" do
      let(:first_properties) { super().merge(pricing_group_keys: ["region"]) }
      let(:second_properties) { super().merge(pricing_group_keys: ["region"]) }
      let(:event_properties) do
        [[first_event_at, {"region" => "us", "quantity" => 100}],
          [rate_changed_at, {"region" => "us", "quantity" => 10}],
          [second_event_at, {"region" => "eu", "quantity" => 10}]]
      end

      it "skips the exhausted tier for the existing group and charges the first tier for the new group" do
        expect(fees.map { |fee| [fee.rate_card_rate, fee.grouped_by, fee.units, fee.amount_cents] }).to match_array([
          [first_rate, {"region" => "us"}, 100, 10_000],
          [second_rate, {"region" => "us"}, 10, 1_500], # Opens at 100: 10 × $1.50, no first-tier flat fee.
          [second_rate, {"region" => "eu"}, 10, 7_000] # Opens at zero: 10 × $2 + $50.
        ])
      end
    end

    context "when R2 uses graduated percentages", :premium do
      let(:second_model) { "graduated_percentage" }
      let(:second_properties) do
        {graduated_percentage_ranges: [
          {to_value: "50", rate: "1", flat_amount: "12"},
          {to_value: "100", rate: "5", flat_amount: "2"},
          {to_value: nil, rate: "10", flat_amount: "1"}
        ]}
      end

      it "applies only R2's touched rates and flat fees" do
        expect(fees.map(&:amount_cents)).to eq([8_000, 600]) # R2: 20 × 5% + $2 + 20 × 10% + $1
      end
    end

    context "with three segments in the operation" do
      let(:third_start) { Time.zone.parse("2027-01-25") }
      let(:additional_rates) do
        [{code: "r3", effective_from: third_start.iso8601, billing_interval_unit: "month",
          rate_model: "volume", rate_properties: {volume_ranges: [
            {to_value: "125", per_unit_amount: "9", flat_amount: "0"},
            {to_value: nil, per_unit_amount: "3", flat_amount: "0"}
          ]}}]
      end
      let(:event_properties) { super() + [[third_start, {"quantity" => 10}]] }

      it "prices all three segments with just their local sums" do
        queries = capture_sql { fees }
        expect(fees.map(&:amount_cents)).to eq([8_000, 12_000, 3_000]) # R3 closes at 80 + 40 + 10; bills 10 × $3.
        expect(queries.grep(/SELECT .*SUM\(.*FROM "events"/mi).size).to eq(3)
      end

      context "when the middle segment has no events" do
        let(:event_properties) { super().reject { |at, _| at == second_event_at } }
        let(:first_event_properties) { {"quantity" => 120} }

        it "keeps earlier usage for the volume tier" do
          expect(fees.last.amount_cents).to eq(3_000) # R3 closes at 120 + 0 + 10; bills 10 × $3.
        end
      end
    end
  end

  # These cases exclude earlier segments. Same-segment filter isolation is tracked in BIL-749.
  context "with a product filter and earlier-segment usage outside its bucket" do
    let(:metric_filters) { [{key: "region", values: %w[us eu]}] }
    let(:product_filter_code) { "us" }
    let(:flat_amount) { "0" }
    let(:first_event_properties) { {"quantity" => 80, "region" => "eu"} }
    let(:second_event_properties) { {"quantity" => 40, "region" => "us"} }

    it "excludes the earlier segment's nonmatching event from billing and aggregation" do
      fee = fees.sole

      expect(fee).to have_attributes(rate_card_rate: second_rate, units: 40, amount_cents: 8_000,
        product_filter: rate_card.product_filter)
      expect(fee.pay_in_advance_event_id).to eq(Event.find_by!(organization:, timestamp: second_event_at).id)
    end

    context "without the nonmatching event" do
      let(:event_properties) { [[second_event_at, second_event_properties]] }

      it "keeps the matching usage entirely in the first tier" do
        expect(fees.sole).to have_attributes(rate_card_rate: second_rate, units: 40, amount_cents: 8_000)
      end
    end

    context "with the default bucket" do
      let(:product_filter_code) { nil }
      let(:first_event_properties) { {"quantity" => 80, "region" => "us"} }
      let(:second_event_properties) { {"quantity" => 40, "region" => "eu"} }

      it "excludes the earlier segment's filtered usage from the default bucket's tiers" do
        expect(fees.sole).to have_attributes(rate_card_rate: second_rate, units: 40, amount_cents: 8_000,
          product_filter: nil)
      end
    end
  end
end
