# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Metered rate changes on a January cycle-end invoice" do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "USD") }
  let(:start) { Time.utc(2027, 1, 1) }
  let(:first_price_at) { start }
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
  let(:old_model) { :standard }
  let(:new_model) { old_model }
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
    create(:rate_card_rate, organization:, rate_card: card, code: "old", effective_from: first_price_at, rate_model: old_model, rate_properties: old_price)
    create(:contract_rate_card, organization:, contract:, rate_card: card, billing_scope: "cycle",
      effective_date: start.to_date, billing_anchor_date: start.to_date, next_billing_at: close)
  end

  def add_rate(at: switch)
    travel_to(at) do
      api_call do
        post_with_token(organization, "/api/v2/rate_cards/#{card.code}/rates", {rate: {
          code: "new", effective_from: switch.iso8601, billing_interval_unit: "month", rate_model: new_model, rate_properties: new_price
        }})
      end
    end
  end

  def event(at, value, received_at: at, amount_cents: nil, **properties)
    travel_to(received_at) do
      create_event({code: metric.code, external_contract_id: contract.external_id, timestamp: at.utc.strftime("%s.%6N"),
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
    let(:old_model) { :graduated }
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
    let(:old_model) { :volume }
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

  context "when Count switches from standard to volume" do
    let(:aggregation_type) { :count_agg }
    let(:new_model) { :volume }
    let(:new_price) do
      {volume_ranges: [{to_value: "2", per_unit_amount: "5", flat_amount: "0"}, {to_value: nil, per_unit_amount: "3", flat_amount: "4"}]}
    end

    it "selects the tier with three events but charges only the third event at the new price" do
      event(start, 10)
      event(start + 1.day, 20)
      add_rate
      event(switch, 30)

      invoice = bill
      expect(segment_fees(invoice)).to eq([["old", 2, 2 * 100], ["new", 1, (3 + 4) * 100]])
      expect(invoice.fees.find_by!(rate_card_rate: card.rates.find_by!(code: "new")).events_count).to eq(1)
    end
  end

  context "when Sum switches from package to graduated" do
    let(:old_model) { :package }
    let(:old_price) { {free_units: 2, package_size: 5, amount: "1"} }
    let(:new_model) { :graduated }
    let(:new_price) do
      {graduated_ranges: [{to_value: "10", per_unit_amount: "3", flat_amount: "0"}, {to_value: nil, per_unit_amount: "2", flat_amount: "0"}]}
    end

    it "carries all eight units, including free units, into the new tiers" do
      event(start, 8)
      add_rate
      event(switch, 7)

      # Six paid units require two packages. The next seven units span two tiers.
      expect(segment_fees(bill)).to eq([["old", 8, 2 * 100], ["new", 7, (2 * 3 + 5 * 2) * 100]])
    end
  end

  context "when Sum switches from graduated to package" do
    let(:old_model) { :graduated }
    let(:old_price) do
      {graduated_ranges: [{from_value: 0, to_value: 5, per_unit_amount: "3", flat_amount: "0"},
        {from_value: 5, to_value: nil, per_unit_amount: "2", flat_amount: "0"}]}
    end
    let(:new_model) { :package }
    let(:new_price) { {free_units: 2, package_size: 5, amount: "1"} }

    it "starts a fresh allowance and bills one package for the five paid units" do
      event(start, 8)
      add_rate
      event(switch, 7)

      expect(segment_fees(bill)).to eq([["old", 8, (5 * 3 + 3 * 2) * 100], ["new", 7, 100]])
    end
  end

  context "when volume pricing switches to another model" do
    let(:aggregation_type) { :count_agg }
    let(:old_model) { :volume }
    let(:old_price) do
      {volume_ranges: [{from_value: 0, to_value: 2, per_unit_amount: "1", flat_amount: "2"},
        {from_value: 2, to_value: nil, per_unit_amount: "3", flat_amount: "4"}]}
    end
    let(:new_model) { :standard }
    let(:new_price) { {amount: "2"} }
    let(:first_values) { [1, 1] }
    let(:later_value) { 1 }
    let(:old_units) { 2 }
    let(:new_units) { 1 }
    let(:old_amount_cents) { 400 } # Two events × $1 + $2 flat.
    let(:new_amount_cents) { new_units * 200 }

    shared_examples "switches away from volume pricing" do
      it "bills only the new segment's units under standard pricing" do
        first_values.each_with_index { |value, index| event(start + index.days, value) }
        add_rate
        event(switch, later_value)

        expect(usage_cents(switch + 1.day)).to eq([old_amount_cents, new_amount_cents])
        expect(segment_fees(bill)).to eq([["old", old_units, old_amount_cents], ["new", new_units, new_amount_cents]])
      end

      context "when the new rate is graduated" do
        let(:new_model) { :graduated }
        let(:new_price) do
          {graduated_ranges: [{to_value: "2", per_unit_amount: "5", flat_amount: "7"},
            {to_value: nil, per_unit_amount: "3", flat_amount: "4"}]}
        end
        let(:new_amount_cents) { new_units * 300 + 400 } # Earlier usage exhausted the first tier; charge only the upper tier's flat.

        it "keeps the opening tier position without rebilling volume units" do
          first_values.each_with_index { |value, index| event(start + index.days, value) }
          add_rate
          event(switch, later_value)

          expect(usage_cents(switch + 1.day)).to eq([old_amount_cents, new_amount_cents])
          expect(segment_fees(bill)).to eq([["old", old_units, old_amount_cents], ["new", new_units, new_amount_cents]])
        end
      end
    end

    include_examples "switches away from volume pricing"

    context "with Sum aggregation" do
      let(:aggregation_type) { :sum_agg }
      let(:first_values) { [4, 4] }
      let(:later_value) { 7 }
      let(:old_units) { 8 }
      let(:new_units) { 7 }
      let(:old_amount_cents) { (8 * 3 + 4) * 100 }

      include_examples "switches away from volume pricing"
    end
  end

  context "with late usage across package and graduated rates" do
    let(:old_model) { :package }
    let(:old_price) { {free_units: 2, package_size: 5, amount: "1"} }
    let(:new_model) { :graduated }
    let(:new_price) do
      {graduated_ranges: [{to_value: "10", per_unit_amount: "3", flat_amount: "4"},
        {to_value: nil, per_unit_amount: "2", flat_amount: "6"}]}
    end

    it "recomputes packages and the later tier's applicable flat amount for late first-segment usage" do
      event(start, 8)
      add_rate
      event(switch, 7)
      expect(usage_cents(switch + 1.day)).to eq([200, (2 * 3 + 4 + 5 * 2 + 6) * 100])

      event(start + 9.days, 5, received_at: switch + 2.days)

      # Old: ceil((13 - 2) / 5) packages; new: all seven units now fall in the upper tier.
      expect(usage_cents(switch + 3.days)).to eq([300, (7 * 2 + 6) * 100])
      expect(segment_fees(bill)).to eq([["old", 13, 300], ["new", 7, 2000]])
    end

    context "when graduated pricing switches to package pricing" do
      let(:old_model) { :graduated }
      let(:old_price) do
        {graduated_ranges: [{from_value: 0, to_value: 5, per_unit_amount: "3", flat_amount: "4"},
          {from_value: 5, to_value: nil, per_unit_amount: "2", flat_amount: "6"}]}
      end
      let(:new_model) { :package }
      let(:new_price) { {free_units: 2, package_size: 5, amount: "1"} }

      it "recomputes only the later packages when late usage belongs to the second segment" do
        event(start, 8)
        add_rate
        event(switch, 7)
        expect(usage_cents(switch + 1.day)).to eq([(5 * 3 + 4 + 3 * 2 + 6) * 100, 100])

        event(switch + 1.day, 5, received_at: switch + 2.days)

        expect(usage_cents(switch + 3.days)).to eq([3100, 200]) # ceil((12 - 2) / 5) packages.
        expect(segment_fees(bill)).to eq([["old", 8, 3100], ["new", 12, 200]])
      end
    end
  end

  context "with two graduated percentage rates", :premium do
    let(:old_model) { :graduated_percentage }
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
    let(:old_model) { :package }
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
    let(:old_model) { :percentage }
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
      expect(usage_cents(switch + 1.day)).to eq([1000, 2000])
      invoice = bill
      expect(segment_fees(invoice)).to eq([["old", 10, 1000], ["new", 10, 2000]])
      expect(invoice.fees.order(Arel.sql("properties->>'from_datetime'")).pluck(:events_count)).to eq([1, 1])
    end

    context "when the new rate uses percentage pricing", :premium do
      let(:new_model) { :percentage }
      let(:new_price) { {rate: "10", per_transaction_min_amount: "0.01"} }
      let(:later_value) { 3 }
      let(:event_counts) { [1, 1] }
      let(:new_amount_cents) { 100 }
      let(:event_properties) { {} }

      before do
        event(start, 10, **event_properties)
        add_rate
        event(switch, later_value, **event_properties) unless later_value.nil?
      end

      shared_examples "prices the carried maximum" do
        it "charges the carried maximum while keeping event counts segment-local" do
          # The carried $10 maximum at 10% costs $1 before transaction limits and fixed fees.
          expect(usage_cents(switch + 1.day)).to eq([1000, new_amount_cents])
          invoice = bill
          expect(segment_fees(invoice)).to eq([["old", 10, 1000], ["new", 10, new_amount_cents]])
          expect(invoice.fees.order(Arel.sql("properties->>'from_datetime'")).pluck(:events_count)).to eq(event_counts)
        end
      end

      include_examples "prices the carried maximum"

      context "when the later event reports zero" do
        let(:later_value) { 0 }

        include_examples "prices the carried maximum"
      end

      context "with a fixed event fee" do
        let(:new_price) { super().merge(fixed_amount: "2") }
        let(:new_amount_cents) { 100 + 200 } # $10 × 10% plus one $2 event fee.

        include_examples "prices the carried maximum"
      end

      context "with a monetary free allowance" do
        let(:new_price) { super().merge(free_units_per_total_aggregation: "5") }
        let(:new_amount_cents) { 50 } # ($10 carried maximum - $5 segment allowance) × 10%.

        include_examples "prices the carried maximum"

        context "when the second segment has no events" do
          let(:later_value) { nil }
          let(:event_counts) { [1, 0] }

          include_examples "prices the carried maximum"
        end

        context "without transaction limits" do
          let(:new_price) { super().except(:per_transaction_min_amount) }

          include_examples "prices the carried maximum"

          context "when the second segment has no events" do
            let(:later_value) { nil }
            let(:event_counts) { [1, 0] }

            include_examples "prices the carried maximum"
          end
        end
      end

      context "with a free first event before a zero local maximum" do
        let(:new_price) { super().merge(free_units_per_events: 1) }
        let(:later_value) { -3 }
        let(:event_counts) { [1, 2] }

        before { event(switch + 1.hour, 0) }

        # The negative event is free; the zero maximum's event bills the carried $10 at 10%.
        include_examples "prices the carried maximum"
      end

      context "when the second segment has no events" do
        let(:later_value) { nil }
        let(:event_counts) { [1, 0] }

        include_examples "prices the carried maximum"

        context "with a binding minimum" do
          let(:new_price) { super().merge(per_transaction_min_amount: "2") }
          let(:new_amount_cents) { 200 }

          include_examples "prices the carried maximum"
        end

        context "with a binding maximum" do
          let(:new_price) { super().merge(per_transaction_max_amount: "0.50") }
          let(:new_amount_cents) { 50 }

          include_examples "prices the carried maximum"
        end

        context "with a fixed event fee" do
          let(:new_price) { super().merge(fixed_amount: "2") }

          include_examples "prices the carried maximum"
        end
      end

      context "without a transaction minimum" do
        let(:new_price) { {rate: "10"} }

        include_examples "prices the carried maximum"
      end

      context "with regional pricing" do
        let(:old_price) { super().merge(pricing_group_keys: ["region"]) }
        let(:new_price) { super().merge(pricing_group_keys: ["region"]) }
        let(:event_properties) { {region: "EU"} }
        let(:eu_amount_cents) { 100 }
        let(:us_amount_cents) { 200 }

        shared_examples "prices regional closing maxima" do
          it "prices each group's carried maximum independently" do
            event(start, 20, region: "US")

            expect(usage_cents(switch + 1.day)).to eq([3000, eu_amount_cents + us_amount_cents])
            invoice = bill
            expect(invoice.fees.map { |fee| [fee.rate_card_rate.code, fee.grouped_by, fee.units, fee.amount_cents, fee.events_count] })
              .to match_array([
                ["old", {"region" => "EU"}, 10, 1000, 1],
                ["old", {"region" => "US"}, 20, 2000, 1],
                ["new", {"region" => "EU"}, 10, eu_amount_cents, 1],
                ["new", {"region" => "US"}, 20, us_amount_cents, 0]
              ])
          end
        end

        include_examples "prices regional closing maxima"

        context "with monetary free allowances" do
          let(:new_price) { super().merge(free_units_per_total_aggregation: "5") }
          let(:eu_amount_cents) { 50 } # ($10 EU maximum - $5 EU allowance) × 10%.
          let(:us_amount_cents) { 150 } # ($20 US maximum - $5 US allowance) × 10%.

          include_examples "prices regional closing maxima"
        end
      end
    end
  end

  context "with dynamic pricing of a non-prorated sum", :premium do
    let(:old_model) { :dynamic }
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

    before do
      event(start, 31)
      add_rate
      event(switch, 31)
    end

    it "weights the accumulated units for the days served at each price" do
      expect(segment_fees(bill).map(&:last)).to eq([15 * 100, 32 * 200]) # 31 × 15/31, then 62 × 16/31.
    end

    context "when the new rate is graduated" do
      let(:new_model) { :graduated }
      let(:new_price) do
        {graduated_ranges: [{to_value: "40", per_unit_amount: "31", flat_amount: "0"}, {to_value: nil, per_unit_amount: "62", flat_amount: "0"}]}
      end

      it "splits the 62 full units across tiers before weighting both by 16/31" do
        expect(segment_fees(bill)).to eq([["old", 31, 15 * 100], ["new", 62, (40 * 100 + 22 * 200) * 16]])
      end
    end

    context "when the new rate is volume" do
      let(:new_model) { :volume }
      let(:new_price) do
        {volume_ranges: [{to_value: "40", per_unit_amount: "31", flat_amount: "0"}, {to_value: nil, per_unit_amount: "62", flat_amount: "0"}]}
      end

      it "selects the upper tier with 62 full units and charges for 32 weighted units" do
        expect(segment_fees(bill)).to eq([["old", 31, 15 * 100], ["new", 62, 32 * 6200]])
      end
    end
  end

  context "with latest aggregation" do
    let(:aggregation_type) { :latest_agg }

    it "retains the latest timestamped value through an eventless segment" do
      event(start + 2.days, 7)
      add_rate
      event(start, 10, received_at: switch + 1.day)
      expect(usage_cents(switch + 2.days)).to eq([700, 1400])
      invoice = bill
      expect(segment_fees(invoice)).to eq([["old", 7, 700], ["new", 7, 1400]])
      expect(invoice.fees.order(Arel.sql("properties->>'from_datetime'")).pluck(:events_count)).to eq([2, 0])
    end

    it "uses the later segment's own latest value even if an older event arrives last" do
      event(start, 7)
      add_rate
      event(switch + 1.day, 5)
      event(switch, 9, received_at: switch + 2.days)
      expect(segment_fees(bill)).to eq([["old", 7, 700], ["new", 5, 1000]])
    end

    context "with regional pricing" do
      let(:old_price) { super().merge(pricing_group_keys: ["region"]) }
      let(:new_price) { super().merge(pricing_group_keys: ["region"]) }

      it "bills only the carried region when the new segment has no events" do
        event(start, 7, region: "EU")
        add_rate
        expect(usage_cents(switch + 1.day)).to eq([700, 1400])
        expect(bill.fees.where(rate_card_rate: card.rates.find_by!(code: "new")).pluck(:grouped_by, :units, :events_count))
          .to eq([[{"region" => "EU"}, 7, 0]])
      end

      it "keeps the eventless region's value and honors an explicit zero in the other" do
        event(start, 7, region: "EU")
        event(start, 9, region: "US")
        add_rate
        event(switch, 0, region: "US")
        expect(usage_cents(switch + 1.day)).to eq([1600, 1400])
        invoice = bill
        expect(invoice.fees.where(rate_card_rate: card.rates.find_by!(code: "new")).pluck(:grouped_by, :units, :events_count))
          .to match_array([[{"region" => "EU"}, 7, 0], [{"region" => "US"}, 0, 1]])
      end

      context "when the new rate groups by another property" do
        let(:new_price) { super().merge(pricing_group_keys: ["zone"]) }

        it "does not import groups observed under the previous rate" do
          event(start, 7, region: "EU", zone: "north")
          add_rate
          event(switch, 2, region: "US", zone: "south")
          expect(segment_fees(bill)).to eq([["old", 7, 700], ["new", 2, 400]])
        end
      end
    end
  end

  context "with closing-value pricing model changes" do
    let(:aggregation_type) { :max_agg }
    let(:later_value) { 20 }
    let(:new_units) { 20 }
    let(:new_amounts) do
      {
        graduated: (5 * 1 + 2 + 15 * 3 + 4) * 100,
        volume: (20 * 3 + 4) * 100,
        package: 4 * 300 # ceil((20 - 2) / 5) packages.
      }
    end
    let(:new_prices) do
      {
        graduated: {graduated_ranges: [{to_value: "5", per_unit_amount: "1", flat_amount: "2"},
          {to_value: nil, per_unit_amount: "3", flat_amount: "4"}]},
        volume: {volume_ranges: [{to_value: "15", per_unit_amount: "2", flat_amount: "1"},
          {to_value: nil, per_unit_amount: "3", flat_amount: "4"}]},
        package: {free_units: 2, package_size: 5, amount: "3"}
      }
    end

    shared_examples "prices the segment's closing value" do
      %i[graduated volume package].each do |model|
        context "when the new rate uses #{model} pricing" do
          let(:new_model) { model }
          let(:new_price) { new_prices.fetch(model) }

          it "prices the full closing value and leaves the first segment unchanged" do
            event(start, 10)
            add_rate
            event(switch, later_value)

            expect(usage_cents(switch + 1.day)).to eq([1000, new_amounts.fetch(model)])
            expect(segment_fees(bill)).to eq([["old", 10, 1000], ["new", new_units, new_amounts.fetch(model)]])
          end
        end
      end
    end

    include_examples "prices the segment's closing value"

    context "with Latest aggregation" do
      let(:aggregation_type) { :latest_agg }

      include_examples "prices the segment's closing value"

      context "when the later value decreases" do
        let(:later_value) { 4 }
        let(:new_units) { 4 }
        let(:new_amounts) do
          {graduated: (4 * 1 + 2) * 100, volume: (4 * 2 + 1) * 100, package: 300}
        end

        include_examples "prices the segment's closing value"
      end
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

      context "when the new rate is graduated" do
        let(:new_model) { :graduated }
        let(:new_price) do
          {graduated_ranges: [{to_value: "2", per_unit_amount: "31", flat_amount: "0"}, {to_value: nil, per_unit_amount: "62", flat_amount: "0"}]}
        end

        it "prices the carried identifiers in the lower tier and the new identifier in the upper tier" do
          # A and B occupy the first tier for five and sixteen days; C occupies the second for sixteen.
          expect(segment_fees(bill)).to eq([["old", 2, 2 * 15 * 100], ["new", 2, (5 + 16) * 100 + 16 * 200]])
        end
      end

      context "when the new rate is volume" do
        let(:new_model) { :volume }
        let(:new_price) do
          {volume_ranges: [{to_value: "2", per_unit_amount: "31", flat_amount: "0"}, {to_value: nil, per_unit_amount: "62", flat_amount: "0"}]}
        end

        it "uses three closing identifiers to select the tier and bills each active day, including removal day" do
          event(switch + 1.day, "d", operation_type: "add")

          # A: five days, B and C: sixteen each, D: fifteen; three remain at close.
          expect(segment_fees(bill)).to eq([["old", 2, 2 * 15 * 100], ["new", 3, (5 + 2 * 16 + 15) * 200]])
        end
      end
    end
  end

  context "with prorated identifiers removed around the rate change" do
    let(:aggregation_type) { :unique_count_agg }
    let(:recurring) { true }
    let(:proration) { true }
    let(:pricing_group_keys) { ["region"] }
    let(:old_price) { {amount: "31", pricing_group_keys:} }
    let(:new_price) { {amount: "62", pricing_group_keys:} }
    let(:removed_at) { start + 9.days }
    let(:identifier_events) do
      [[start + 1.hour, "a", "add", "EU"], [start + 2.hours, "b", "add", "EU"], [removed_at, "a", "remove", "EU"]]
    end
    let(:expected_usage) { [2500, 3200] } # A: ten days, B: fifteen days at $31/31; then B: sixteen days at $62/31.
    let(:expected_fees) do
      [["old", {"region" => "EU"}, 1, 2500], ["new", {"region" => "EU"}, 1, 3200]]
    end

    before do
      identifier_events.sort_by(&:first).each do |timestamp, identifier, operation, region|
        event(timestamp, identifier, operation_type: operation, region:)
      end
      add_rate
    end

    shared_examples "bills only the identifier's active days" do
      it "keeps removed identifiers out of later coverage and retains the removal day" do
        expect(usage_cents(close - 1.hour)).to eq(expected_usage)
        invoice = bill
        expect(invoice.fees.map { |fee| [fee.rate_card_rate.code, fee.grouped_by, fee.units, fee.amount_cents] })
          .to match_array(expected_fees)
      end
    end

    include_examples "bills only the identifier's active days"

    context "without regional pricing" do
      let(:pricing_group_keys) { [] }
      let(:expected_fees) { [["old", {}, 1, 2500], ["new", {}, 1, 3200]] }

      include_examples "bills only the identifier's active days"
    end

    context "when the removal occurs exactly at the switch" do
      let(:removed_at) { switch }
      let(:expected_usage) { [3000, 3400] } # A and B: fifteen old-rate days; A: one new-rate day, B: sixteen.
      let(:expected_fees) do
        [["old", {"region" => "EU"}, 2, 3000], ["new", {"region" => "EU"}, 1, 3400]]
      end

      include_examples "bills only the identifier's active days"
    end

    context "when no identifiers remain active in the first region" do
      let(:identifier_events) do
        super() + [[start + 3.hours, "c", "add", "US"], [start + 10.days, "b", "remove", "EU"]]
      end
      let(:expected_usage) { [3600, 3200] } # EU: (10 + 11) days; US: fifteen old-rate and sixteen new-rate days.
      let(:expected_fees) do
        [
          ["old", {"region" => "EU"}, 0, 2100],
          ["old", {"region" => "US"}, 1, 1500],
          ["new", {"region" => "US"}, 1, 3200]
        ]
      end

      include_examples "bills only the identifier's active days"
    end
  end

  context "with weighted sum" do
    let(:aggregation_type) { :weighted_sum_agg }
    let(:recurring) { true }

    it "weights the running quantity across both segments by the full 31 days" do
      event(start, 31)
      add_rate
      event(switch, 31)
      expect(usage_cents(switch + 1.day)).to eq([1500, 400]) # 62 units active for one of 31 days at $2.
      expect(segment_fees(bill)).to eq([["old", 15, 1500], ["new", 32, 6400]]) # 31 × 15/31, then 62 × 16/31.
    end

    it "weights a late increase only for the days it is active" do
      event(start, 31)
      add_rate
      event(close - 2.days, 31)

      expect(segment_fees(bill)).to eq([["old", 15, 1500], ["new", 18, 3600]]) # 31 × 16/31 + 31 × 2/31.
    end

    shared_examples "recomputes weighted history across a rate change" do
      it "weights a decrease only after its timestamp" do
        event(start, 31)
        add_rate
        event(switch + 4.days, -31)

        expect(usage_cents(switch + 5.days)).to eq([1500, 800])
        expect(segment_fees(bill)).to eq([["old", 15, 1500], ["new", 4, 800]]) # 31 × 15/31, then 31 × 4/31 at $2.
      end

      it "replaces the fallback price when the second rate is created after its usage" do
        event(start, 31)
        event(switch, 31)
        expect(usage_cents(switch + 12.hours)).to eq([1600]) # (31 × 15 + 62 × 0.5) / 31 at $1.

        add_rate(at: switch + 13.hours)

        expect(usage_cents(switch + 1.day)).to eq([1500, 400]) # 31 × 15/31 at $1; 62 × 1/31 at $2.
        expect(segment_fees(bill)).to eq([["old", 15, 1500], ["new", 32, 6400]])
      end

      it "updates the second segment's opening quantity for a late first-segment event" do
        event(start, 31)
        add_rate
        expect(usage_cents(switch + 1.day)).to eq([1500, 200])

        event(start + 9.days, 31, received_at: switch + 2.days)

        expect(usage_cents(switch + 3.days)).to eq([2100, 1200]) # Old: 31 × 15/31 + 31 × 6/31; new: 62 × 3/31 at $2.
        expect(segment_fees(bill)).to eq([["old", 21, 2100], ["new", 32, 6400]])
      end
    end

    include_examples "recomputes weighted history across a rate change"

    context "with non-recurring weighted history" do
      let(:recurring) { false }

      include_examples "recomputes weighted history across a rate change"
    end

    context "when the metric is non-recurring and the second segment has no events" do
      let(:recurring) { false }

      before do
        event(start, 31)
        add_rate
      end

      it "retains the running quantity in current usage after the switch" do
        expect(usage_cents(switch + 1.day)).to eq([1500, 200]) # 31 × 15/31 at $1, then 31 × 1/31 at $2.
      end

      it "invoices both weighted segments at cycle end" do
        invoice = bill

        expect(segment_fees(invoice)).to eq([["old", 15, 1500], ["new", 16, 3200]]) # 31 × 15/31 at $1, then 31 × 16/31 at $2.
        expect(invoice.total_amount_cents).to eq(1500 + 3200)
      end
    end

    context "with non-recurring weighted variation and metric rounding" do
      let(:recurring) { false }
      let(:metric) do
        create(:weighted_sum_billable_metric, organization:, field_name: "value", rounding_function: "floor", rounding_precision: 0)
      end
      let(:new_model) { :volume }
      let(:new_price) do
        {volume_ranges: [{to_value: "20", per_unit_amount: "2", flat_amount: "0"},
          {to_value: nil, per_unit_amount: "10", flat_amount: "0"}]}
      end

      it "carries the unweighted fraction and selects tiers using only local weighted units" do
        event(start, "31.5")
        add_rate

        # floor(31.5 × 15/31) = 15; floor(31.5 × 16/31) = 16, below the 20-unit volume threshold.
        invoice = bill
        expect(segment_fees(invoice)).to eq([["old", 15, 1500], ["new", 16, 3200]])
        expect(invoice.fees.order(Arel.sql("properties->>'from_datetime'")).pluck(:events_count)).to eq([1, 0])
      end
    end

    context "with non-recurring cycle-local history" do
      let(:recurring) { false }
      let(:first_price_at) { start + 4.days }
      let(:event_properties) { {} }

      shared_examples "bounds weighted history to priced coverage" do
        it "excludes earlier unpriced events and resets at the next cycle" do
          event(start, 100, **event_properties)
          event(first_price_at, 27, **event_properties)
          add_rate

          expect(usage_cents(switch + 1.day)).to eq([1100, 200]) # 27 × 11/27 and 27 × 1/27.
          expect(segment_fees(bill)).to eq([["old", 11, 1100], ["new", 16, 3200]]) # 27 × 11/27 and 27 × 16/27.

          event(close, 28, **event_properties)
          expect(usage_cents(close + 1.day)).to eq([200]) # 28 × 1/28 at $2.
          travel_to(close + 1.month) do
            clock_job { BillingOperations::ScheduleJob.perform_now(customer.id) }
            expect(segment_fees(customer.invoices.order(:created_at).last)).to eq([["new", 28, 5600]])
          end
        end
      end

      include_examples "bounds weighted history to priced coverage"

      context "with regional pricing" do
        let(:old_price) { super().merge(pricing_group_keys: ["region"]) }
        let(:new_price) { super().merge(pricing_group_keys: ["region"]) }
        let(:event_properties) { {region: "EU"} }

        include_examples "bounds weighted history to priced coverage"
      end
    end

    context "when the contract ends on January 21" do
      let(:close) { Time.utc(2027, 1, 21) }
      let(:contract) { create(:contract, organization:, customer:, started_at: start, ended_at: close) }

      it "uses the same 20-day cycle for current usage and the closing invoice" do
        event(start, 20)
        add_rate

        expect(usage_cents(switch + 1.day)).to eq([1500, 200])
        expect(segment_fees(bill)).to eq([["old", 15, 1500], ["new", 5, 1000]]) # 20 × 15/20, then 20 × 5/20.
      end
    end

    context "when a draft covers only part of the calendar month", :premium do
      let(:first_price_at) { start + 4.days }
      let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "USD", invoice_grace_period: 3) }

      shared_examples "refreshes weighted usage over priced coverage" do
        it "uses the 27 priced days for current usage, the invoice and draft refresh" do
          event(first_price_at, 27)
          add_rate
          expect(usage_cents(switch + 1.day)).to eq([1100, 200]) # 27 × 11/27 at $1, then 27 × 1/27 at $2.
          invoice = bill
          expect(invoice).to be_draft
          expect(segment_fees(invoice)).to eq([["old", 11, 1100], ["new", 16, 3200]]) # Jan 5–15, then Jan 16–31.

          event(switch, 27, received_at: close + 1.hour)
          travel_to(close + 2.hours) do
            api_call { put_with_token(organization, "/api/v2/invoices/#{invoice.id}/refresh") }
          end
          expect(segment_fees(invoice.reload)).to eq([["old", 11, 1100], ["new", 32, 6400]]) # 54 × 16/27.
        end
      end

      include_examples "refreshes weighted usage over priced coverage"

      context "when the metric is non-recurring" do
        let(:recurring) { false }

        include_examples "refreshes weighted usage over priced coverage"
      end
    end

    context "with regional pricing" do
      let(:old_price) { super().merge(pricing_group_keys: ["region"]) }
      let(:new_price) { super().merge(pricing_group_keys: ["region"]) }

      it "carries an eventless group's running quantity without counting another event" do
        event(start, 31, region: "EU")
        add_rate
        event(switch, 62, region: "US")

        expect(usage_cents(switch + 1.day)).to eq([1500, (1 + 2) * 200])
        expect(bill.fees.where(rate_card_rate: card.rates.find_by!(code: "new")).pluck(:grouped_by, :units, :events_count))
          .to match_array([[{"region" => "EU"}, 16, 0], [{"region" => "US"}, 32, 1]])
      end

      context "with non-recurring groups" do
        let(:recurring) { false }

        it "keeps each group's opening quantity separate when only one group has later usage" do
          event(start, 31, region: "EU")
          event(start, 93, region: "US")
          add_rate
          event(switch, 31, region: "EU")

          expect(usage_cents(switch + 1.day)).to eq([6000, 1000]) # Old: (31 + 93) × 15/31; new: (62 + 93) × 1/31 at $2.
          invoice = bill
          expect(invoice.fees.map { |fee| [fee.rate_card_rate.code, fee.grouped_by, fee.units, fee.amount_cents, fee.events_count] })
            .to match_array([
              ["old", {"region" => "EU"}, 15, 1500, 1],
              ["old", {"region" => "US"}, 45, 4500, 1],
              ["new", {"region" => "EU"}, 32, 6400, 1],
              ["new", {"region" => "US"}, 48, 9600, 0]
            ])
        end
      end
    end
  end

  context "with fractional timestamps around the switch" do
    let(:before_switch) { switch - Rational(1, 1000) }
    let(:after_switch) { switch + Rational(1, 1000) }
    let(:new_units) { 110 }
    let(:new_amount_cents) { 22_000 } # (10 + 100) units at $2.

    shared_examples "assigns boundary events exactly once" do
      it "uses the usage timestamp despite reversed receipt order" do
        add_rate(at: switch - 1.day)
        event(after_switch, 100, received_at: switch + 1.hour)
        event(before_switch, 1, received_at: switch + 2.hours)
        event(switch, 10, received_at: switch + 3.hours)

        expect(organization.events.where(code: metric.code).order(:timestamp).pluck(:timestamp))
          .to eq([before_switch, switch, after_switch])
        expect(usage_cents(switch + 4.hours)).to eq([100, new_amount_cents])
        invoice = bill
        expect(segment_fees(invoice)).to eq([["old", 1, 100], ["new", new_units, new_amount_cents]])
        expect(invoice.fees.order(Arel.sql("properties->>'from_datetime'")).pluck(:events_count)).to eq([1, 2])
      end
    end

    include_examples "assigns boundary events exactly once"

    context "with Count aggregation" do
      let(:aggregation_type) { :count_agg }
      let(:new_units) { 2 }
      let(:new_amount_cents) { 400 }

      include_examples "assigns boundary events exactly once"
    end
  end
end
