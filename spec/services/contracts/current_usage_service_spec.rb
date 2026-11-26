# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::CurrentUsageService do
  subject(:result) { described_class.call!(contract:, timestamp:, apply_taxes:, filters:) }

  let(:filters) { {} }
  let(:organization) { create(:organization, feature_flags: [:product_catalog]) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2027-01-01")) }
  let(:timestamp) { Time.zone.parse("2027-02-10 12:00:00") }
  let(:apply_taxes) { false }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
  let(:early_event_properties) { {} }
  let(:product) { create(:product, :metered, organization:, billable_metric:) }
  let(:billing_timing) { :arrears }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, currency: "EUR") }
  let(:effective_date) { Date.new(2027, 1, 1) }
  let(:units) { nil }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, units:,
      effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
  end
  let(:rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-01-01"),
      rate_properties: {"amount" => "2"})
  end

  before do
    contract_rate_card
    rate
    [Time.zone.parse("2027-01-10"), Time.zone.parse("2027-02-05")].each do |event_timestamp|
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: billable_metric.code, timestamp: event_timestamp, properties: early_event_properties)
    end
  end

  it "prices the window open at the timestamp" do
    usage = result.rate_card_usages.sole

    expect(usage.contract_rate_card).to eq(contract_rate_card)
    expect(usage.obligation.segments.sole).not_to respond_to(:save!)
    expect(usage.obligation.segments.sole).to have_attributes(
      rate:, started_at: Time.zone.parse("2027-02-01"),
      ended_at: Time.zone.parse("2027-03-01")
    )
    expect(usage.fees.sole).to be_new_record
    expect(usage.fees.sole).to have_attributes(fee_type: "product", contract_rate_card:, units: 1, amount_cents: 200)
    expect(result).to have_attributes(contract:, amount_cents: 200, taxes_amount_cents: 0, total_amount_cents: 200)
  end

  it "persists nothing" do
    expect { result }.not_to change { [Fee.count, LegacyBillingSegment.count] }
  end

  context "with an earlier timestamp" do
    let(:timestamp) { Time.zone.parse("2027-01-20 12:00:00") }

    it "prices the window open at that timestamp" do
      usage = result.rate_card_usages.sole

      expect(usage.started_at).to eq(Time.zone.parse("2027-01-01"))
      expect(usage.fees.sole).to have_attributes(units: 1, amount_cents: 200)
    end
  end

  ContractRateCard::BILLING_SCOPES.each_value do |scope|
    context "with #{scope} billing and a mid-cycle rate change" do
      let(:timestamp) { Time.zone.parse("2027-02-15 12:00:00") }
      let(:rate_change_at) { Time.zone.parse("2027-02-15") }
      let(:late_event_at) { rate_change_at + 1.hour }
      let(:late_event_properties) { {} }
      let(:contract_rate_card) do
        create(:contract_rate_card, organization:, contract:, rate_card:, units:, billing_scope: scope,
          effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
      end
      let(:new_rate) do
        create(:rate_card_rate, organization:, rate_card:, effective_from: rate_change_at,
          rate_properties: {"amount" => "5"})
      end

      before do
        new_rate
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: billable_metric.code, timestamp: late_event_at, properties: late_event_properties)
      end

      it "prices the selected obligation in one usage entry" do
        usage = result.rate_card_usages.sole
        expect(usage.obligation.segments.map(&:rate)).to eq(
          (scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)) ? [rate, new_rate] : [new_rate]
        )
        expected_rates = (scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)) ? [rate, new_rate] : [new_rate]
        expect(usage).to have_attributes(
          started_at: Time.zone.parse((expected_rates.size == 2) ? "2027-02-01" : "2027-02-15"),
          ended_at: BillingSegment.inclusive_end(Time.zone.parse("2027-03-01"))
        )
        expect(usage.segments.map(&:rate_properties)).to eq(expected_rates.map(&:properties))
        expect(usage.fees.map { |fee| [fee.units, fee.amount_cents] }).to eq(
          (scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)) ? [[1, 200], [1, 500]] : [[1, 500]]
        )
      end

      context "when querying before the known rate change" do
        let(:timestamp) { Time.zone.parse("2027-02-10 12:00:00") }
        let(:apply_taxes) { true }

        before do
          create(:customer_applied_tax, customer:, tax: create(:tax, organization:, rate: 20))
        end

        it "retains future cycle coverage without pricing future metered usage" do
          usage = result.rate_card_usages.sole

          expect(usage.obligation.segments.map(&:rate)).to eq(
            (scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)) ? [rate, new_rate] : [rate]
          )
          expect(usage.fees.sole).to have_attributes(units: 1, amount_cents: 200)
          expected_end = (scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)) ? "2027-03-01" : "2027-02-15"
          expect(usage.ended_at).to eq(BillingSegment.inclusive_end(Time.zone.parse(expected_end)))
          expect(result).to have_attributes(amount_cents: 200, taxes_amount_cents: 40, total_amount_cents: 240)
        end
      end

      context "when querying at the rate change" do
        let(:timestamp) { Time.zone.parse("2027-02-15") }
        let(:apply_taxes) { true }

        before do
          create(:customer_applied_tax, customer:, tax: create(:tax, organization:, rate: 20))
        end

        it "includes earlier usage only when it belongs to the selected obligation" do
          usage = result.rate_card_usages.sole
          expect(usage.segments.map(&:rate_properties)).to eq(
            ((scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)) ? [rate, new_rate] : [new_rate]).map(&:properties)
          )
          expect(usage.fees.map { |fee| [fee.units, fee.amount_cents] }).to eq(
            (scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)) ? [[1, 200], [0, 0]] : [[0, 0]]
          )
          amount = (scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)) ? 200 : 0
          expect(result).to have_attributes(amount_cents: amount, taxes_amount_cents: amount / 5, total_amount_cents: amount * 6 / 5)
        end
      end

      context "with taxes" do
        let(:apply_taxes) { true }

        before do
          create(:customer_applied_tax, customer:, tax: create(:tax, organization:, rate: 20))
        end

        it "taxes every fee of the selected obligation" do
          expected_amounts = (scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)) ? [200, 500] : [500]
          expect(result.rate_card_usages.sole.fees.map(&:units)).to eq(expected_amounts.map { 1 })
          expect(result.rate_card_usages.sole.fees.map(&:taxes_amount_cents)).to eq(expected_amounts.map { it / 5 })
          expect(result).to have_attributes(amount_cents: expected_amounts.sum,
            taxes_amount_cents: expected_amounts.sum / 5, total_amount_cents: expected_amounts.sum * 6 / 5)
        end
      end

      context "with later events already ingested" do
        before do
          [timestamp, timestamp + 1.second, Time.zone.parse("2027-02-25")].each do |event_timestamp|
            create(:event, organization:, customer:, external_subscription_id: contract.external_id,
              code: billable_metric.code, timestamp: event_timestamp)
          end
        end

        it "includes the query instant but excludes events after it" do
          expect(result.rate_card_usages.sole.fees.map(&:amount_cents)).to eq(
            (scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)) ? [200, 1000] : [1000]
          ) # Earlier slice: one €2 event; current slice: two €5 events through the query instant.
        end
      end

      context "with graduated rates on both slices" do
        let(:graduated_properties) do
          {"graduated_ranges" => [{"from_value" => 0, "to_value" => nil, "per_unit_amount" => "2", "flat_amount" => "3"}]}
        end
        let(:rate) do
          create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-01-01"),
            rate_model: :graduated, rate_properties: graduated_properties)
        end
        let(:new_rate) do
          create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-02-15"),
            rate_model: :graduated, rate_properties: graduated_properties)
        end

        it "prices each slice independently rather than combining usage across rates or cycles" do
          expected = (scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)) ? [500, 500] : [500]

          expect(result.rate_card_usages.sole.fees.map { |fee| [fee.units, fee.amount_cents] }).to eq(expected.map { [1, it] })
          expect(result).to have_attributes(amount_cents: expected.sum, taxes_amount_cents: 0, total_amount_cents: expected.sum)
          # Each slice: one event * €2 + €3 flat; the January event belongs to another cycle.
        end
      end

      context "with three segments in the cycle" do
        let(:timestamp) { Time.zone.parse("2027-02-20 12:00:00") }
        let(:apply_taxes) { true }
        let(:third_rate) do
          create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-02-25"),
            rate_properties: {"amount" => "8"})
        end

        before do
          third_rate
          create(:customer_applied_tax, customer:, tax: create(:tax, organization:, rate: 20))
          [Time.zone.parse("2027-02-20 13:00:00"), Time.zone.parse("2027-02-26")].each do |event_timestamp|
            create(:event, organization:, customer:, external_subscription_id: contract.external_id,
              code: billable_metric.code, timestamp: event_timestamp)
          end
        end

        it "returns the whole selected obligation and prices only eligible events" do
          usage = result.rate_card_usages.sole
          cycle = scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)
          expected_rates = cycle ? [rate, new_rate, third_rate] : [new_rate]
          expect(usage.obligation.segments.map(&:rate)).to eq(expected_rates)
          expect(usage).to have_attributes(
            started_at: Time.zone.parse(cycle ? "2027-02-01" : "2027-02-15"),
            ended_at: BillingSegment.inclusive_end(Time.zone.parse(cycle ? "2027-03-01" : "2027-02-25")),
            rate_source: "rate"
          )
          expect(usage.segments.map { [it.rate_properties, it.amount_cents] }).to eq(
            cycle ? [[rate.properties, 200], [new_rate.properties, 500], [third_rate.properties, 0]] : [[new_rate.properties, 500]]
          )
          expect(usage.fees.map { |fee| [fee.units, fee.events_count, fee.amount_cents, fee.taxes_amount_cents] }).to eq(
            cycle ? [[1, 1, 200, 40], [1, 1, 500, 100]] : [[1, 1, 500, 100]]
          )
          expect(result).to have_attributes(amount_cents: cycle ? 700 : 500,
            taxes_amount_cents: cycle ? 140 : 100, total_amount_cents: cycle ? 840 : 600)
        end

        context "when querying in the final segment" do
          let(:timestamp) { Time.zone.parse("2027-02-27") }

          it "prices every eligible segment with its own rate" do
            usage = result.rate_card_usages.sole
            cycle = scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)
            expect(usage.obligation.segments.map(&:rate)).to eq(cycle ? [rate, new_rate, third_rate] : [third_rate])
            expect(usage.segments.map(&:rate_properties)).to eq((cycle ? [rate, new_rate, third_rate] : [third_rate]).map(&:properties))
            expect(usage.fees.map { |fee| [fee.events_count, fee.amount_cents, fee.taxes_amount_cents] }).to eq(
              cycle ? [[1, 200, 40], [2, 1000, 200], [1, 800, 160]] : [[1, 800, 160]]
            )
          end
        end
      end

      if scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)
        context "with events at the rate change and cycle end" do
          let(:cycle_end) { Time.zone.parse("2027-03-01") }
          let(:timestamp) { BillingSegment.inclusive_end(cycle_end) }
          let(:late_event_at) { rate_change_at }

          before do
            create(:event, organization:, customer:, external_subscription_id: contract.external_id,
              code: billable_metric.code, timestamp: cycle_end)
          end

          it "assigns each boundary event to the segment that starts there" do
            february_usage = result.rate_card_usages.sole
            march_result = described_class.call!(contract:, timestamp: cycle_end, apply_taxes:, filters:)
            march_usage = march_result.rate_card_usages.sole

            expect(february_usage).to have_attributes(
              started_at: Time.zone.parse("2027-02-01"), ended_at: timestamp, units: 2, events_count: 2
            )
            expect(february_usage.segments.map { [it.rate_properties, it.units, it.events_count, it.amount_cents] }).to eq(
              [[rate.properties, 1, 1, 200], [new_rate.properties, 1, 1, 500]]
            ) # Feb 5 at €2; Feb 15 at €5; the Mar 1 event is excluded.
            expect(result).to have_attributes(amount_cents: 200 + 500, taxes_amount_cents: 0, total_amount_cents: 200 + 500)

            expect(march_usage.segments.sole).to have_attributes(
              started_at: cycle_end, rate_properties: new_rate.properties, units: 1, events_count: 1, amount_cents: 500
            ) # Only the Mar 1 event, at the €5 rate.
            expect(march_result).to have_attributes(amount_cents: 500, taxes_amount_cents: 0, total_amount_cents: 500)
          end
        end

        [
          [:sum_billable_metric, [3, 4], [3, 4]],
          [:max_billable_metric, [7, 9], [7, 9]],
          [:unique_count_billable_metric, %w[Alice Alice], [1, 1]]
        ].each do |metric_factory, values, segment_units|
          context "with a nonrecurring #{metric_factory.to_s.delete_suffix("_billable_metric")} metric" do
            let(:billable_metric) { create(metric_factory, organization:, recurring: false) }
            let(:early_event_properties) { {item_id: values.first} }
            let(:late_event_properties) { {item_id: values.last} }

            it "sums the priced segments' units, not a whole-cycle aggregation" do
              usage = result.rate_card_usages.sole
              old_units, new_units = segment_units
              old_amount = old_units * 200
              new_amount = new_units * 500

              expect(usage.segments.map { [it.rate_properties, it.units, it.events_count, it.amount_cents] }).to eq(
                [[rate.properties, old_units, 1, old_amount], [new_rate.properties, new_units, 1, new_amount]]
              )
              expect(usage.segments.map { it.fees.size }).to eq([1, 1])
              expect(usage).to have_attributes(units: old_units + new_units, events_count: 2, amount_cents: old_amount + new_amount)
              expect(result).to have_attributes(
                amount_cents: old_amount + new_amount, taxes_amount_cents: 0, total_amount_cents: old_amount + new_amount
              )
            end
          end
        end

        context "with a New York customer" do
          let(:customer) { create(:customer, organization:, timezone: "America/New_York", currency: "EUR") }
          let(:timestamp) { Time.utc(2027, 3, 1, 4, 59) } # Still February locally.
          let(:rate_change_at) { Time.utc(2027, 2, 15) } # Feb 14 at 19:00 EST.
          let(:late_event_at) { rate_change_at }

          before do
            create(:event, organization:, customer:, external_subscription_id: contract.external_id,
              code: billable_metric.code, timestamp: rate_change_at - 1.second)
          end

          it "uses the local cycle window and splits events at the persisted rate-change instant" do
            expect(new_rate.effective_from).to eq(rate_change_at)

            usage = result.rate_card_usages.sole
            cycle_start = Time.utc(2027, 2, 1, 5)
            cycle_end = BillingSegment.inclusive_end(Time.utc(2027, 3, 1, 5))

            expect(usage).to have_attributes(started_at: cycle_start, ended_at: cycle_end, units: 3, events_count: 3)
            expect(usage.segments.map { [it.started_at, it.ended_at] }).to eq(
              [[cycle_start, BillingSegment.inclusive_end(rate_change_at)], [rate_change_at, cycle_end]]
            )
            expect(usage.segments.map { [it.rate_properties, it.units, it.events_count, it.amount_cents] }).to eq(
              [[rate.properties, 2, 2, 2 * 200], [new_rate.properties, 1, 1, 500]]
            ) # Feb 5 and one second before the change at €2 each; the boundary event at €5.
            expect(result).to have_attributes(amount_cents: 2 * 200 + 500, taxes_amount_cents: 0, total_amount_cents: 2 * 200 + 500)
          end
        end
      end
    end

    context "with #{scope} billing before the first priced cycle" do
      let(:contract_rate_card) do
        create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope: scope,
          effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
      end
      let(:rate) do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-03-01"),
          rate_properties: {"amount" => "2"})
      end

      it "does not search forward for usage" do
        expect(result.rate_card_usages).to eq([])
        expect(result.amount_cents).to eq(0)
      end

      context "when pricing starts later in this cycle" do
        let(:rate) do
          create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-02-15"),
            rate_properties: {"amount" => "2"})
        end

        it "returns no usage before pricing starts" do
          expect(result.rate_card_usages).to eq([])
          expect(result.amount_cents).to eq(0)
        end
      end
    end
  end

  context "when a metered card has no current obligation" do
    let(:rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-03-01"),
        rate_properties: {"amount" => "2"})
    end

    before { create(:product_filter, organization:, product:) }

    it "does not load the pricing filter tree" do
      statements = capture_sql { result }

      expect(result.rate_card_usages).to eq([])
      expect(statements.grep(/FROM "(product_filters|product_filter_values|billable_metric_filters)"/i)).to be_empty
    end
  end

  context "with multiple pricing slices in a custom pricing unit" do
    let(:pricing_unit) { create(:pricing_unit, organization:, code: "credits") }
    let(:rate_card) do
      create(:rate_card, organization:, product:, currency: "EUR", applied_pricing_unit_code: pricing_unit.code)
    end
    let(:rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-01-01"),
        rate_properties: {"amount" => "2"}, applied_pricing_unit_conversion_rate: 2)
    end
    let(:timestamp) { Time.zone.parse("2027-02-20") }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-02-15"),
        rate_properties: {"amount" => "4"}, applied_pricing_unit_conversion_rate: 2)
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: billable_metric.code, timestamp: Time.zone.parse("2027-02-16"))
    end

    it "loads pricing units once and converts every slice" do
      statements = capture_sql { result }

      expect(statements.grep(/FROM "pricing_units"/i).size).to eq(1)
      expect(result.rate_card_usages.sole.fees.map(&:amount_cents)).to eq([400, 800]) # 2 and 4 credits * €2 per credit * 100 cents.
    end

    context "with another card billed by segment" do
      let(:other_rate_card) do
        create(:rate_card, organization:, product: create(:product, :metered, organization:, billable_metric:),
          currency: "EUR", applied_pricing_unit_code: pricing_unit.code)
      end

      before do
        create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card, billing_scope: :segment,
          effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
        create(:rate_card_rate, organization:, rate_card: other_rate_card, effective_from: Time.zone.parse("2027-01-01"),
          rate_properties: {"amount" => "2"}, applied_pricing_unit_conversion_rate: 2)
        create(:rate_card_rate, organization:, rate_card: other_rate_card, effective_from: Time.zone.parse("2027-02-15"),
          rate_properties: {"amount" => "4"}, applied_pricing_unit_conversion_rate: 2)
      end

      it "selects each obligation independently while loading pricing units once" do
        statements = capture_sql { result }
        amounts = result.rate_card_usages.to_h { |usage| [usage.contract_rate_card.rate_card, usage.fees.map(&:amount_cents)] }

        expect(amounts).to eq(rate_card => [400, 800], other_rate_card => [800])
        expect(statements.grep(/FROM "pricing_units"/i).size).to eq(1)
      end
    end
  end

  context "when the contract has ended" do
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at: Time.zone.parse("2027-01-01"),
        ended_at: Time.zone.parse("2027-02-01"), terminated_at: Time.zone.parse("2027-02-01"))
    end

    it "returns no current usage" do
      expect(result.rate_card_usages).to eq([])
      expect(result).to have_attributes(amount_cents: 0, taxes_amount_cents: 0, total_amount_cents: 0)
    end

    context "with a timestamp before termination" do
      let(:timestamp) { Time.zone.parse("2027-01-20 12:00:00") }

      it "still prices the window open at that timestamp" do
        expect(result.rate_card_usages.sole.fees.sole).to have_attributes(units: 1, amount_cents: 200)
      end
    end
  end

  context "when the card is not effective yet" do
    let(:effective_date) { Date.new(2027, 2, 15) }

    it "returns no window" do
      expect(result.rate_card_usages).to eq([])
      expect(result).to have_attributes(amount_cents: 0, taxes_amount_cents: 0, total_amount_cents: 0)
    end
  end

  context "when the contract was canceled after its start date" do
    let(:contract) do
      create(:contract, :canceled, organization:, customer:, started_at: Time.zone.parse("2027-01-01"),
        canceled_at: Time.zone.parse("2027-02-01"))
    end

    it "returns no usage even though its cards and matching events exist" do
      expect(result.rate_card_usages).to eq([])
      expect(result).to have_attributes(amount_cents: 0, taxes_amount_cents: 0, total_amount_cents: 0)
    end
  end

  context "with a newer version of the card" do
    let(:new_rate_card) { create(:rate_card, organization:, product:, currency: "EUR") }
    let(:new_contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card: new_rate_card,
        effective_date: Date.new(2027, 2, 1), billing_anchor_date: Date.new(2027, 2, 1))
    end

    before do
      new_contract_rate_card
      create(:rate_card_rate, organization:, rate_card: new_rate_card, effective_from: Time.zone.parse("2027-02-01"),
        rate_properties: {"amount" => "5"})
    end

    it "prices the version effective at the timestamp only" do
      usage = result.rate_card_usages.sole

      expect(usage.contract_rate_card).to eq(new_contract_rate_card)
      expect(usage.fees.sole).to have_attributes(units: 1, amount_cents: 500)
    end

    context "when filtering on the superseded version" do
      let(:filters) { {rate_card_code: rate_card.code} }

      it "returns no window" do
        expect(result.rate_card_usages).to eq([])
      end
    end
  end

  context "with an intro phase" do
    let(:intro_phase) do
      create(:rate_phase, :contract_level, organization:, contract_rate_card:, plan_rate_card: nil, code: "intro",
        position: 1, billing_interval_cycle_count: 2,
        rate_override: create(:rate_override, organization:, rate_properties: {"amount" => "1"}))
    end

    before { intro_phase }

    it "prices the window with the phase override" do
      usage = result.rate_card_usages.sole

      expect(usage.rate_phase).to eq(intro_phase)
      expect(usage.obligation.cycle.phase.rate_override).to eq(intro_phase.rate_override)
      expect(usage.fees.sole).to have_attributes(units: 1, amount_cents: 100)
    end

    context "when the phase is over" do
      let(:timestamp) { Time.zone.parse("2027-03-10 12:00:00") }

      it "prices the window with the card's rate" do
        usage = result.rate_card_usages.sole

        expect(usage.rate_phase).to be_nil
        expect(usage.obligation.cycle.phase.rate_override).to be_nil
      end
    end
  end

  context "with a customer timezone behind UTC" do
    let(:customer) { create(:customer, organization:, timezone: "America/Argentina/Buenos_Aires", currency: "EUR") }
    # Jan 31, 23:00 in the customer timezone.
    let(:timestamp) { Time.utc(2027, 2, 1, 2) }
    let(:new_rate_card) { create(:rate_card, organization:, product:, currency: "EUR") }

    before do
      create(:contract_rate_card, organization:, contract:, rate_card: new_rate_card,
        effective_date: Date.new(2027, 2, 1), billing_anchor_date: Date.new(2027, 2, 1))
      create(:rate_card_rate, organization:, rate_card: new_rate_card, effective_from: Time.utc(2027, 2, 1, 3))
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: billable_metric.code, timestamp: Time.utc(2027, 2, 1, 1))
    end

    it "prices the customer's local window with the version effective on the customer's date" do
      usage = result.rate_card_usages.sole

      expect(usage.contract_rate_card).to eq(contract_rate_card)
      expect(usage).to have_attributes(
        started_at: Time.utc(2027, 1, 1, 3), ended_at: BillingSegment.inclusive_end(Time.utc(2027, 2, 1, 3))
      )
      expect(usage.units).to eq(2)
    end

    context "when the customer's day has turned" do
      let(:timestamp) { Time.utc(2027, 2, 1, 3, 30) }

      it "prices the next local window with the new version" do
        usage = result.rate_card_usages.sole

        expect(usage.contract_rate_card.rate_card).to eq(new_rate_card)
        expect(usage.started_at).to eq(Time.utc(2027, 2, 1, 3))
      end
    end
  end

  context "when the contract is pending" do
    let(:contract) { create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2027-01-01")) }

    it "returns the contract with no window" do
      expect(result.rate_card_usages).to eq([])
      expect(result).to have_attributes(contract:, amount_cents: 0, taxes_amount_cents: 0, total_amount_cents: 0)
    end
  end

  context "when the contract is a draft whose start has passed" do
    let(:contract) { create(:contract, :draft, organization:, customer:, started_at: Time.zone.parse("2027-01-01")) }

    it "returns the contract with no window" do
      expect(result.rate_card_usages).to eq([])
      expect(result).to have_attributes(contract:, amount_cents: 0, taxes_amount_cents: 0, total_amount_cents: 0)
    end
  end

  context "with a product type filter" do
    let(:filters) { {product_type: "fixed"} }
    let(:fixed_rate_card) do
      create(:rate_card, organization:, product: create(:product, :fixed, organization:), currency: "EUR")
    end

    before do
      create(:contract_rate_card, organization:, contract:, rate_card: fixed_rate_card, units: 1,
        effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
      create(:rate_card_rate, organization:, rate_card: fixed_rate_card, effective_from: Time.zone.parse("2027-01-01"),
        rate_properties: {"amount" => "10"})
    end

    it "prices the matching cards only" do
      expect(result.rate_card_usages.map { |usage| usage.contract_rate_card.rate_card }).to eq([fixed_rate_card])
      expect(result.amount_cents).to eq(1000)
    end
  end

  context "with a card scoped to a product filter and a card on another product" do
    let(:eu_filter) { create(:product_filter, organization:, product:) }
    let(:eu_rate_card) { create(:rate_card, organization:, product:, product_filter: eu_filter, currency: "EUR") }
    let(:other_product) { create(:product, :metered, organization:, billable_metric:) }
    let(:other_rate_card) { create(:rate_card, organization:, product: other_product, currency: "EUR") }
    let(:priced_cards) do
      result.rate_card_usages.to_h { |usage| [usage.contract_rate_card.rate_card, usage.units] }
    end

    before do
      region = create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[eu us])
      create(:product_filter_value, organization:, product_filter: eu_filter, billable_metric_filter: region, value: "eu")
      [eu_rate_card, other_rate_card].each do |scoped_rate_card|
        create(:contract_rate_card, organization:, contract:, rate_card: scoped_rate_card,
          effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
        create(:rate_card_rate, organization:, rate_card: scoped_rate_card, effective_from: Time.zone.parse("2027-01-01"))
      end
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: billable_metric.code, timestamp: Time.zone.parse("2027-02-06"), properties: {region: "eu"})
    end

    it "prices each card on the events it targets" do
      expect(priced_cards).to eq(rate_card => 1, eu_rate_card => 1, other_rate_card => 2)
    end

    context "with a product code filter" do
      let(:filters) { {product_code: product.code} }

      it "prices the cards of that product only" do
        expect(priced_cards.keys).to contain_exactly(rate_card, eu_rate_card)
      end

      it "does not load units for the selected metered cards" do
        statements = capture_sql { result }

        expect(statements.grep(/FROM "contract_rate_cards_terms"/i)).to be_empty
      end
    end

    context "with a product filter code filter" do
      let(:filters) { {product_filter_code: eu_filter.code} }

      it "prices the card scoped to that filter only" do
        expect(priced_cards.keys).to eq([eu_rate_card])
      end
    end

    context "with filters no card matches together" do
      let(:filters) { {product_code: other_product.code, product_filter_code: eu_filter.code} }

      it "returns no usage" do
        expect(result.rate_card_usages).to eq([])
      end
    end
  end

  context "with an unknown product type" do
    subject(:result) { described_class.call(contract:, timestamp:, apply_taxes:, filters:) }

    let(:filters) { {product_type: "usage"} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq(product_type: ["value_is_invalid"])
    end
  end

  context "with several cards" do
    let(:rate_card) { create(:rate_card, organization:, product:, currency: "EUR", code: "a_monthly") }
    let(:codes) { result.rate_card_usages.map { |usage| usage.contract_rate_card.rate_card.code } }

    before do
      [
        ["b_mid_month", Date.new(2027, 1, 1), Date.new(2027, 1, 15), "month"],
        ["c_weekly", Date.new(2027, 2, 1), Date.new(2027, 2, 1), "week"]
      ].each do |code, effective_date, billing_anchor_date, billing_interval_unit|
        other_rate_card = create(:rate_card, organization:, code:, currency: "EUR",
          product: create(:product, :metered, organization:, billable_metric:))
        create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card, effective_date:, billing_anchor_date:)
        create(:rate_card_rate, organization:, rate_card: other_rate_card, billing_interval_unit:,
          effective_from: effective_date.in_time_zone)
      end
    end

    it "orders the windows by start" do
      expect(codes).to eq(%w[b_mid_month a_monthly c_weekly])
    end

    context "with windows opening at the same instant" do
      let(:timestamp) { Time.zone.parse("2027-02-03 12:00:00") }

      it "puts the window closing first ahead" do
        expect(codes).to eq(%w[b_mid_month c_weekly a_monthly])
      end
    end
  end

  context "without a rate" do
    let(:rate) { nil }

    it "returns no window" do
      expect(result.rate_card_usages).to eq([])
    end
  end

  context "when the contract ended before the timestamp" do
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at: Time.zone.parse("2027-01-01"),
        ended_at: Time.zone.parse("2027-02-01"), terminated_at: Time.zone.parse("2027-02-01"))
    end

    it "returns no window" do
      expect(result.rate_card_usages).to eq([])
    end
  end

  # Terminating before a card's start leaves it no window, and no schedule to build.
  context "when a card starts after the contract ends" do
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at: Time.zone.parse("2027-01-01"),
        terminated_at: Time.zone.parse("2027-02-01"))
    end
    let(:effective_date) { Date.new(2027, 2, 5) }

    it "returns no window" do
      expect(result.rate_card_usages).to eq([])
    end
  end

  context "with taxes" do
    let(:apply_taxes) { true }

    before do
      create(:customer_applied_tax, customer:, tax: create(:tax, organization:, rate: 20))
    end

    it "applies the customer taxes" do
      expect(result.rate_card_usages.sole.fees.sole).to have_attributes(taxes_amount_cents: 40)
      expect(result).to have_attributes(amount_cents: 200, taxes_amount_cents: 40, total_amount_cents: 240)
    end
  end

  context "when the customer is linked to a tax provider" do
    let(:apply_taxes) { true }
    let(:integration) { create(:anrok_integration, organization:) }
    let(:endpoint) { "https://api.nango.dev/action/trigger" }

    before do
      create(:anrok_customer, integration:, customer:)
      create(:netsuite_collection_mapping, integration:, mapping_type: :fallback_item,
        settings: {external_id: "1", external_account_code: "11", external_name: ""})
      create(:rate_card_applied_tax, rate_card:, tax: create(:tax, organization:, rate: 20))

      stub_request(:post, endpoint).to_return do |request|
        response = JSON.parse(File.read(Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response.json")))
        provider_fee = response["succeededInvoices"].first["fees"].last
        response["succeededInvoices"].first["fees"] = JSON.parse(request.body)["input"].first["fees"].map do |fee|
          provider_fee.deep_dup.tap do |item|
            item["item_key"] = fee["item_key"]
            item["amount_cents"] = fee["amount_cents"]
            item["tax_amount_cents"] = 17
            item["tax_breakdown"].first["tax_amount"] = 17
          end
        end

        {body: response.to_json}
      end
    end

    it "takes the taxes from the provider instead of the local ones" do
      expect(result.rate_card_usages.sole.fees.sole).to have_attributes(taxes_amount_cents: 17)
      expect(result).to have_attributes(amount_cents: 200, taxes_amount_cents: 17, total_amount_cents: 217, taxes_unavailable: false)
    end

    context "with multiple pricing slices" do
      let(:timestamp) { Time.zone.parse("2027-02-20") }

      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-02-15"),
          rate_properties: {"amount" => "5"})
        create(:event, organization:, customer:, external_subscription_id: contract.external_id,
          code: billable_metric.code, timestamp: Time.zone.parse("2027-02-16"))
      end

      it "sends all fees in one provider request and applies each response" do
        expect(result.rate_card_usages.sole.fees.map(&:taxes_amount_cents)).to eq([17, 17])
        expect(result).to have_attributes(amount_cents: 700, taxes_amount_cents: 34, total_amount_cents: 734)
        expect(WebMock).to have_requested(:post, endpoint).once
      end

      context "with another card billed by segment" do
        let(:other_rate_card) do
          create(:rate_card, organization:, product: create(:product, :metered, organization:, billable_metric:), currency: "EUR")
        end

        before do
          create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card, billing_scope: :segment,
            effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
          create(:rate_card_rate, organization:, rate_card: other_rate_card, effective_from: Time.zone.parse("2027-01-01"),
            rate_properties: {"amount" => "2"})
          create(:rate_card_rate, organization:, rate_card: other_rate_card, effective_from: Time.zone.parse("2027-02-15"),
            rate_properties: {"amount" => "5"})
        end

        it "taxes both selected obligations in one provider request" do
          amounts = result.rate_card_usages.to_h { |usage| [usage.contract_rate_card.rate_card, usage.fees.map(&:amount_cents)] }

          expect(amounts).to eq(rate_card => [200, 500], other_rate_card => [500])
          expect(result).to have_attributes(amount_cents: 1200, taxes_amount_cents: 51, total_amount_cents: 1251)
          expect(WebMock).to have_requested(:post, endpoint).once
        end
      end
    end

    context "when the provider cannot resolve the taxes" do
      subject(:result) { described_class.call(contract:, timestamp:, apply_taxes:, filters:) }

      before do
        stub_request(:post, endpoint)
          .to_return(body: File.read(Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json")))
      end

      it "returns a failure of the provider instead of usage" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
        expect(result.error).to have_attributes(third_party: "anrok", error_code: nil, error_message: "taxDateTooFarInFuture: Service failure")
      end
    end

    context "when the provider throttles the request" do
      subject(:result) { described_class.call(contract:, timestamp:, apply_taxes:, filters:) }

      before do
        allow(Throttling).to receive(:for).with(:anrok).and_return(instance_double(Throttling::Base, check: false))
      end

      it "returns a too many provider requests failure instead of usage" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::TooManyProviderRequestsFailure)
        expect(result.error).to have_attributes(provider_name: :anrok, message: "Service anrok is not available. Try again later.")
        expect(WebMock).not_to have_requested(:post, endpoint)
      end
    end

    context "when the provider's request limit is reached" do
      subject(:result) { described_class.call(contract:, timestamp:, apply_taxes:, filters:) }

      before do
        stub_request(:post, endpoint).to_return(status: 429, body: {error: {code: "SSS_REQUEST_LIMIT_EXCEEDED"}}.to_json)
      end

      it "returns a too many provider requests failure instead of usage" do
        expect(result.error).to be_a(BaseService::TooManyProviderRequestsFailure)
        expect(result.error).to have_attributes(provider_name: "anrok", error: an_instance_of(Integrations::Aggregator::RequestLimitError))
      end
    end

    context "when the provider fails with a transient error" do
      subject(:result) { described_class.call(contract:, timestamp:, apply_taxes:, filters:) }

      before { stub_request(:post, endpoint).to_return(status: 502, body: "") }

      it "returns a failure of the provider instead of usage" do
        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
        expect(result.error).to have_attributes(third_party: "anrok", error_code: nil)
      end
    end

    context "when the provider does not answer in time" do
      subject(:result) { described_class.call(contract:, timestamp:, apply_taxes:, filters:) }

      before { stub_request(:post, endpoint).to_raise(Net::ReadTimeout) }

      it "returns a failure of the provider instead of usage" do
        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
        expect(result.error).to have_attributes(third_party: "anrok", error_code: nil, error_message: start_with("Net::ReadTimeout"))
      end
    end

    context "when untaxed usage is accepted on a provider failure" do
      subject(:result) { described_class.call(contract:, timestamp:, apply_taxes:, untaxed_on_provider_failure: true, filters:) }

      before { stub_request(:post, endpoint).to_raise(Net::ReadTimeout) }

      it "returns the untaxed usage flagged as such" do
        expect(result).to be_success
        expect(result).to have_attributes(amount_cents: 200, taxes_amount_cents: 0, total_amount_cents: 200, taxes_unavailable: true)
        expect(WebMock).to have_requested(:post, endpoint).once
      end

      context "when the provider throttles the request" do
        before do
          allow(Throttling).to receive(:for).with(:anrok).and_return(instance_double(Throttling::Base, check: false))
        end

        it "returns the untaxed usage flagged as such" do
          expect(result).to have_attributes(amount_cents: 200, taxes_amount_cents: 0, taxes_unavailable: true)
        end
      end

      context "when the provider cannot resolve the taxes" do
        before do
          stub_request(:post, endpoint)
            .to_return(body: File.read(Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json")))
        end

        it "returns the untaxed usage flagged as such" do
          expect(result).to have_attributes(amount_cents: 200, taxes_amount_cents: 0, taxes_unavailable: true)
        end
      end
    end

    context "when taxes are skipped" do
      let(:apply_taxes) { false }

      it "does not call the provider" do
        expect(result).to have_attributes(amount_cents: 200, taxes_amount_cents: 0, total_amount_cents: 200)
        expect(WebMock).not_to have_requested(:post, endpoint)
      end
    end
  end

  context "with a fixed card" do
    let(:product) { create(:product, :fixed, organization:) }
    let(:units) { 3 }
    let(:rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-01-01"),
        rate_properties: {"amount" => "10"})
    end

    it "prices the card's units for the window" do
      usage = result.rate_card_usages.sole

      expect(usage.fees.sole).to have_attributes(fee_type: "product", units: 3, amount_cents: 3000)
    end

    context "with a mid-cycle price change and proration" do
      let(:timestamp) { Time.zone.parse("2027-02-20") }
      let(:rate_card) { create(:rate_card, organization:, product:, currency: "EUR", proration: true) }

      before do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-02-15"),
          rate_properties: {"amount" => "20"})
      end

      it "prices both slices without changing their coverage or proration" do
        usage = result.rate_card_usages.sole

        expect(usage.fees.map(&:amount_cents)).to eq([1500, 3000]) # 3 units * €10 or €20 * 14 / 28 days.
        expect(usage.fees.map { it.properties.values_at("from_datetime", "to_datetime") }).to eq([
          [Time.zone.parse("2027-02-01").iso8601(6), BillingSegment.inclusive_end(Time.zone.parse("2027-02-15")).iso8601(6)],
          [Time.zone.parse("2027-02-15").iso8601(6), BillingSegment.inclusive_end(Time.zone.parse("2027-03-01")).iso8601(6)]
        ])
      end

      ContractRateCard::BILLING_SCOPES.each_value do |scope|
        context "with #{scope} billing before the price change" do
          let(:timestamp) { Time.zone.parse("2027-02-10") }
          let(:contract_rate_card) do
            create(:contract_rate_card, organization:, contract:, rate_card:, units:, billing_scope: scope,
              effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
          end

          it "previews the selected fixed coverage without clipping it at the query instant" do
            usage = result.rate_card_usages.sole
            expected = (scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)) ? [1500, 3000] : [1500]

            expect(usage.segments.first.rate_properties).to eq(rate.properties)
            expect(usage.segments.map(&:amount_cents)).to eq(expected) # 3 units * €10/€20 * 14 / 28 days per slice.
            expect(usage.fees.first.properties.values_at("from_datetime", "to_datetime")).to eq([
              Time.zone.parse("2027-02-01").iso8601(6), BillingSegment.inclusive_end(Time.zone.parse("2027-02-15")).iso8601(6)
            ])
            expect(result).to have_attributes(amount_cents: expected.sum, taxes_amount_cents: 0, total_amount_cents: expected.sum)
          end
        end
      end

      context "with three fixed segments and a query in the middle" do
        let(:timestamp) { Time.zone.parse("2027-02-20") }

        before do
          create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-02-25"),
            rate_properties: {"amount" => "30"})
        end

        it "prices the entire cycle including the future segment" do
          usage = result.rate_card_usages.sole
          expect(usage.obligation.segments.map(&:started_at)).to eq(
            %w[2027-02-01 2027-02-15 2027-02-25].map { Time.zone.parse(it) }
          )
          expect(usage).to have_attributes(started_at: Time.zone.parse("2027-02-01"),
            ended_at: BillingSegment.inclusive_end(Time.zone.parse("2027-03-01")))
          expect(usage.segments.map { [it.rate_properties["amount"], it.amount_cents] }).to eq([["10", 1500], ["20", 2143], ["30", 1286]])
          # 3 units * €10 * 14/28, €20 * 10/28, and €30 * 4/28 days, rounded in cents.
        end
      end
    end

    context "with multiple fixed cards" do
      let(:second_product) { create(:product, :fixed, organization:) }
      let(:second_rate_card) { create(:rate_card, organization:, product: second_product, currency: "EUR") }

      before do
        create(:contract_rate_card, organization:, contract:, rate_card: second_rate_card,
          units: 4, effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
        create(:rate_card_rate, organization:, rate_card: second_rate_card,
          effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "10"})
      end

      it "loads all card units in one query" do
        contract_rate_card
        second_rate_card

        statements = capture_sql { result }

        expect(result.rate_card_usages.size).to eq(2)
        expect(statements.grep(/FROM "contract_rate_cards_terms"/i).size).to eq(1)
      end
    end
  end

  context "with a without_product_category filter" do
    let(:filters) { {without_product_category: true} }
    let(:categorized_product) { create(:product, organization:, billable_metric: create(:billable_metric, organization:)) }
    let(:categorized_rate_card) { create(:rate_card, organization:, product: categorized_product, currency: "EUR") }
    let(:product) { create(:product, :standalone, :metered, organization:, billable_metric:) }

    before do
      create(:contract_rate_card, organization:, contract:, rate_card: categorized_rate_card,
        effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
      create(:rate_card_rate, organization:, rate_card: categorized_rate_card,
        effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "9"})
    end

    it "returns only the rate card with no product category" do
      expect(result.rate_card_usages.map { |u| u.contract_rate_card }).to eq([contract_rate_card])
    end
  end

  context "with a product_category_ids filter" do
    let(:filters) { {product_category_ids: [product.product_category.id]} }
    let(:product) { create(:product, :metered, organization:, billable_metric:) }
    let(:other_product) { create(:product, :metered, organization:, billable_metric: create(:billable_metric, organization:)) }
    let(:other_rate_card) { create(:rate_card, organization:, product: other_product, currency: "EUR") }

    before do
      create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card,
        effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
      create(:rate_card_rate, organization:, rate_card: other_rate_card,
        effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "9"})
    end

    it "returns only rate cards whose product matches that category" do
      expect(result.rate_card_usages.map { |u| u.contract_rate_card }).to eq([contract_rate_card])
    end
  end

  context "with without_product_category and product_category_ids both set" do
    let(:categorized_product) { create(:product, organization:, billable_metric: create(:billable_metric, organization:)) }
    let(:categorized_rate_card) { create(:rate_card, organization:, product: categorized_product, currency: "EUR") }
    let(:categorized_contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card: categorized_rate_card,
        effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
    end
    let(:other_categorized_product) { create(:product, organization:, billable_metric: create(:billable_metric, organization:)) }
    let(:other_categorized_rate_card) { create(:rate_card, organization:, product: other_categorized_product, currency: "EUR") }
    let(:other_categorized_contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card: other_categorized_rate_card,
        effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
    end
    let(:product) { create(:product, :standalone, :metered, organization:, billable_metric:) }
    let(:filters) { {without_product_category: true, product_category_ids: [other_categorized_product.product_category.id]} }

    before do
      categorized_contract_rate_card
      create(:rate_card_rate, organization:, rate_card: categorized_rate_card,
        effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "9"})
      other_categorized_contract_rate_card
      create(:rate_card_rate, organization:, rate_card: other_categorized_rate_card,
        effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "7"})
    end

    it "ORs the two conditions - admits both the standalone card and the card whose category is in the list" do
      expect(result.rate_card_usages.map { |u| u.contract_rate_card }).to contain_exactly(contract_rate_card, other_categorized_contract_rate_card)
    end

    it "does not admit a card whose category is neither in the list nor absent" do
      expect(result.rate_card_usages.map { |u| u.contract_rate_card }).not_to include(categorized_contract_rate_card)
    end
  end

  context "with a product_ids filter" do
    let(:filters) { {product_ids: [product.id]} }
    let(:other_product) { create(:product, :metered, organization:, billable_metric: create(:billable_metric, organization:)) }
    let(:other_rate_card) { create(:rate_card, organization:, product: other_product, currency: "EUR") }

    before do
      create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card,
        effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
      create(:rate_card_rate, organization:, rate_card: other_rate_card,
        effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "9"})
    end

    it "returns only the rate card for that product" do
      expect(result.rate_card_usages.map { |u| u.contract_rate_card }).to eq([contract_rate_card])
    end
  end

  context "with a without_product_filter filter" do
    let(:filters) { {without_product_filter: true} }
    let(:product_filter) { create(:product_filter, organization:, product:) }
    let(:filtered_rate_card) { create(:rate_card, organization:, product:, product_filter:, currency: "EUR") }

    before do
      create(:contract_rate_card, organization:, contract:, rate_card: filtered_rate_card,
        effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
      create(:rate_card_rate, organization:, rate_card: filtered_rate_card,
        effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "9"})
    end

    it "returns only the rate card with no product filter" do
      expect(result.rate_card_usages.map { |u| u.contract_rate_card }).to eq([contract_rate_card])
    end
  end

  context "with a product_filter_ids filter" do
    let(:product_filter) { create(:product_filter, organization:, product:) }
    let(:filtered_rate_card) { create(:rate_card, organization:, product:, product_filter:, currency: "EUR") }
    let(:filtered_contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card: filtered_rate_card,
        effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
    end
    let(:filters) { {product_filter_ids: [product_filter.id]} }

    before do
      filtered_contract_rate_card
      create(:rate_card_rate, organization:, rate_card: filtered_rate_card,
        effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "9"})
    end

    it "returns only the rate card whose product_filter is in the list" do
      expect(result.rate_card_usages.map { |u| u.contract_rate_card }).to eq([filtered_contract_rate_card])
    end
  end

  context "with without_product_filter and product_filter_ids both set" do
    let(:other_product_filter) { create(:product_filter, organization:, product:) }
    let(:other_filtered_rate_card) { create(:rate_card, organization:, product:, product_filter: other_product_filter, currency: "EUR") }
    let(:other_filtered_contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card: other_filtered_rate_card,
        effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
    end
    let(:unlisted_product_filter) { create(:product_filter, organization:, product:) }
    let(:unlisted_filtered_rate_card) { create(:rate_card, organization:, product:, product_filter: unlisted_product_filter, currency: "EUR") }
    let(:unlisted_filtered_contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card: unlisted_filtered_rate_card,
        effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
    end
    let(:filters) { {without_product_filter: true, product_filter_ids: [other_product_filter.id]} }

    before do
      other_filtered_contract_rate_card
      create(:rate_card_rate, organization:, rate_card: other_filtered_rate_card,
        effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "9"})
      unlisted_filtered_contract_rate_card
      create(:rate_card_rate, organization:, rate_card: unlisted_filtered_rate_card,
        effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "7"})
    end

    it "ORs the two conditions - admits the no-filter card and the card whose filter is in the list" do
      expect(result.rate_card_usages.map { |u| u.contract_rate_card }).to contain_exactly(contract_rate_card, other_filtered_contract_rate_card)
    end

    it "does not admit a card whose filter is neither in the list nor absent" do
      expect(result.rate_card_usages.map { |u| u.contract_rate_card }).not_to include(unlisted_filtered_contract_rate_card)
    end
  end

  context "with a search_term" do
    subject(:result) { described_class.call!(contract:, timestamp:, apply_taxes:, filters:, search_term:) }

    let(:search_term) { product.name.downcase.first(5) }

    it "matches case-insensitively on product name" do
      expect(result.rate_card_usages.map { |u| u.contract_rate_card }).to eq([contract_rate_card])
    end

    context "when the term matches only the rate card's own name" do
      let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, currency: "EUR", name: "Enterprise tier card") }
      let(:search_term) { "enterprise tier" }

      it "still matches, independent of the product name" do
        expect(result.rate_card_usages.map { |u| u.contract_rate_card }).to eq([contract_rate_card])
      end
    end

    context "when the term matches only the rate card's code" do
      let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, currency: "EUR", code: "ent-tier-42") }
      let(:search_term) { "ent-tier" }

      it "still matches, independent of the rate card's name" do
        expect(result.rate_card_usages.map { |u| u.contract_rate_card }).to eq([contract_rate_card])
      end
    end

    context "when the term matches only the product filter's invoice_display_name" do
      let(:product_filter) { create(:product_filter, organization:, product:, invoice_display_name: "Premium support add-on") }
      let(:rate_card) { create(:rate_card, organization:, product:, product_filter:, billing_timing:, currency: "EUR") }
      let(:search_term) { "premium support" }

      it "still matches, independent of the product and rate card names" do
        expect(result.rate_card_usages.map { |u| u.contract_rate_card }).to eq([contract_rate_card])
      end
    end

    context "when the term matches nothing" do
      let(:search_term) { "zzz-no-match-zzz" }

      it "returns no window" do
        expect(result.rate_card_usages).to eq([])
      end
    end
  end
end
