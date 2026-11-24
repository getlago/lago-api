# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Metered rate changes on a January cycle-end invoice" do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "USD") }
  let(:start) { Time.utc(2027, 1, 1) }
  let(:switch) { Time.utc(2027, 1, 16) }
  let(:close) { Time.utc(2027, 2, 1) }
  let(:contract) { create(:contract, organization:, customer:, started_at: start) }
  let(:aggregation_type) { :sum_agg }
  let(:recurring) { false }
  let(:metric) do
    create(:billable_metric, organization:, aggregation_type:, recurring:, field_name: "value",
      weighted_interval: (:seconds if aggregation_type == :weighted_sum_agg))
  end
  let(:proration) { false }
  let(:card) { create(:rate_card, organization:, product: create(:product, organization:, billable_metric: metric), currency: "USD", proration:) }
  let(:model) { :standard }
  let(:old_price) { {amount: "1"} }
  let(:new_price) { {amount: "2"} }

  around do |example|
    travel_to(start - 1.day)
    example.run
  ensure
    travel_back
  end

  before do
    stub_pdf_generation
    create(:rate_card_rate, organization:, rate_card: card, code: "old", effective_from: start, rate_model: model, rate_properties: old_price)
    create(:contract_rate_card, organization:, contract:, rate_card: card, billing_scope: "cycle",
      effective_date: start.to_date, billing_anchor_date: start.to_date, next_billing_at: close)
  end

  def add_rate(at: switch)
    travel_to(at) do
      api_call do
        post_with_token(organization, "/api/v2/rate_cards/#{card.code}/rates", {rate: {
          code: "new", effective_from: switch.iso8601, billing_interval_unit: "month", rate_model: model, rate_properties: new_price
        }})
      end
    end
  end

  def event(at, value, received_at: at, amount_cents: nil, **properties)
    travel_to(received_at) do
      create_event({code: metric.code, external_contract_id: contract.external_id, timestamp: at.to_i,
                    precise_total_amount_cents: amount_cents, properties: {value:, **properties}}.compact)
    end
  end

  def usage_cents(at)
    travel_to(at) do
      get_with_token(organization, "/api/v2/contracts/#{contract.external_id}/current_usage", {apply_taxes: false})
      expect(response).to have_http_status(:ok)
      json.fetch(:current_usage).fetch(:rate_cards).sole.fetch(:segments).pluck(:amount_cents)
    end
  end

  def bill
    travel_to(close) do
      expect(customer.invoices).to be_empty
      clock_job { BillingOperations::ScheduleJob.perform_now(customer.id) }
      customer.invoices.reload.sole
    end
  end

  def segment_fees(invoice)
    invoice.fees.order(Arel.sql("properties->>'from_datetime'")).map { |fee| [fee.rate_card_rate.code, fee.units, fee.amount_cents] }
  end

  context "when both rates are graduated" do
    let(:model) { :graduated }
    let(:old_price) do
      {graduated_ranges: [{from_value: 0, to_value: 100, per_unit_amount: "2", flat_amount: "0"},
        {from_value: 100, to_value: nil, per_unit_amount: "1", flat_amount: "0"}]}
    end
    let(:new_price) do
      {graduated_ranges: [{to_value: "150", per_unit_amount: "3", flat_amount: "0"}, {to_value: nil, per_unit_amount: "2", flat_amount: "0"}]}
    end

    it "recomputes the fallback price and assigns a late event by its usage timestamp" do
      event(start, 100)
      event(switch, 50)
      expect(usage_cents(switch + 1.hour)).to eq([(100 * 2 + 50) * 100])

      add_rate(at: switch + 2.hours)
      expect(usage_cents(switch + 3.days)).to eq([20_000, 50 * 300])

      event(switch - 1.second, 30, received_at: switch + 4.days)
      expect(usage_cents(switch + 5.days)).to eq([23_000, 12_000])
      invoice = bill
      expect(segment_fees(invoice)).to eq([["old", 130, (100 * 2 + 30) * 100], ["new", 50, (20 * 3 + 30 * 2) * 100]])
      expect(invoice).to have_attributes(created_at: close, total_amount_cents: 35_000)
    end
  end

  context "with counted events and two volume rates" do
    let(:aggregation_type) { :count_agg }
    let(:model) { :volume }
    let(:old_price) { {volume_ranges: [{from_value: 0, to_value: nil, per_unit_amount: "1", flat_amount: "2"}]} }
    let(:new_price) do
      {volume_ranges: [{to_value: "1", per_unit_amount: "5", flat_amount: "0"}, {to_value: nil, per_unit_amount: "3", flat_amount: "4"}]}
    end

    it "uses the closing count to select the tier but bills only the new event and its tier's flat fee" do
      event(start, 1)
      add_rate
      event(switch, 1)
      expect(segment_fees(bill)).to eq([["old", 1, (1 + 2) * 100], ["new", 1, (3 + 4) * 100]])
    end
  end

  context "with two graduated percentage rates", :premium do
    let(:model) { :graduated_percentage }
    let(:old_price) { {graduated_percentage_ranges: [{from_value: 0, to_value: nil, rate: "5", flat_amount: "0"}]} }
    let(:new_price) do
      {graduated_percentage_ranges: [{to_value: "100", rate: "5", flat_amount: "8"}, {to_value: nil, rate: "10", flat_amount: "2"}]}
    end

    it "charges only the percentage and flat fee of the new tier reached" do
      event(start, 100)
      add_rate
      event(switch, 30)
      expect(segment_fees(bill)).to eq([["old", 100, 500], ["new", 30, 300 + 200]])
    end
  end

  context "with free units and packages" do
    let(:model) { :package }
    let(:old_price) { {free_units: 2, package_size: 5, amount: "1"} }
    let(:new_price) { {free_units: 2, package_size: 5, amount: "3"} }

    it "restarts the allowance and rounds packages separately under each rate" do
      event(start, 8)
      add_rate
      event(switch, 7)
      expect(segment_fees(bill)).to eq([["old", 8, 2 * 100], ["new", 7, 1 * 300]]) # 6 paid units, then 5.
    end
  end

  context "with percentage pricing and one free event per segment" do
    let(:model) { :percentage }
    let(:old_price) { {rate: "10", fixed_amount: "1", free_units_per_events: 1, free_units_per_total_aggregation: "0"} }
    let(:new_price) { old_price.merge(rate: "20") }

    it "grants each rate its free event before charging the percentage and fixed fee" do
      event(start, 50)
      event(start + 1.day, 20)
      add_rate
      event(switch, 40)
      event(switch + 1.day, 10)
      expect(segment_fees(bill)).to eq([["old", 70, 200 + 100], ["new", 50, 200 + 100]])
    end
  end

  context "with maximum aggregation" do
    let(:aggregation_type) { :max_agg }

    it "retains the first segment's maximum when the next event is smaller" do
      event(start, 10)
      add_rate
      event(switch, 3)
      expect(segment_fees(bill)).to eq([["old", 10, 1000], ["new", 10, 2000]])
    end
  end

  context "with dynamic pricing of a non-prorated sum", :premium do
    let(:model) { :dynamic }
    let(:old_price) { {} }
    let(:new_price) { {} }

    it "bills only the submitted amount belonging to each segment" do
      event(start, 10, amount_cents: 123)
      add_rate
      event(switch, 20, amount_cents: 456)
      expect(segment_fees(bill)).to eq([["old", 10, 123], ["new", 20, 456]])
    end
  end

  context "with a prorated recurring sum" do
    let(:recurring) { true }
    let(:proration) { true }

    it "weights the accumulated units for the days served at each price" do
      event(start, 31)
      add_rate
      event(switch, 31)
      expect(segment_fees(bill).map(&:last)).to eq([15 * 100, 32 * 200]) # 31 × 15/31, then 62 × 16/31.
    end
  end

  context "with latest aggregation" do
    let(:aggregation_type) { :latest_agg }

    it "retains the latest timestamped value through an eventless segment" do
      event(start + 2.days, 7)
      add_rate
      event(start, 10, received_at: switch + 1.day)
      expect(segment_fees(bill)).to eq([["old", 7, 700], ["new", 7, 1400]])
    end

    it "uses the later segment's own latest value even if an older event arrives last" do
      event(start, 7)
      add_rate
      event(switch + 1.day, 5)
      event(switch, 9, received_at: switch + 2.days)
      expect(segment_fees(bill)).to eq([["old", 7, 700], ["new", 5, 1000]])
    end
  end

  context "with active identifiers" do
    let(:aggregation_type) { :unique_count_agg }
    let(:recurring) { true }
    let(:old_price) { {amount: "31"} }
    let(:new_price) { {amount: "62"} }

    before do
      event(start, "a", operation_type: "add")
      event(start, "b", operation_type: "add")
      add_rate
      event(switch, "c", operation_type: "add")
      event(Time.utc(2027, 1, 20), "a", operation_type: "remove")
    end

    it "prices the identifiers still active at each close" do
      expect(segment_fees(bill)).to eq([["old", 2, 2 * 3100], ["new", 2, 2 * 6200]])
    end

    context "with proration" do
      let(:proration) { true }

      it "includes the removal day and divides both segments by the full 31 days" do
        expect(segment_fees(bill).map(&:last)).to eq([2 * 15 * 100, (2 * 16 + 5) * 200])
      end
    end
  end

  context "with weighted sum" do
    let(:aggregation_type) { :weighted_sum_agg }
    let(:recurring) { true }

    it "weights the running quantity across both segments by the full 31 days" do
      event(start, 31)
      add_rate
      event(switch, 31)
      expect(segment_fees(bill)).to eq([["old", 15, 1500], ["new", 32, 6400]]) # 31 × 15/31, then 62 × 16/31.
    end
  end
end
