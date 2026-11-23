# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::Clickhouse::WeightedSumQuery, clickhouse: {clean_before: true} do
  subject(:event_store) do
    Events::Stores::ClickhouseStore.new(
      code: billable_metric.code,
      billing_context: Billing::Context.from(subscription:),
      boundaries:,
      filters: {grouped_by:}
    )
  end

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:weighted_sum_billable_metric, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, started_at: from_datetime) }
  let(:grouped_by) { nil }

  # 30 days: 2026-11-01 00:00:00 to 2026-12-01 00:00:00 (the store ceils to_datetime), 2,592,000 s
  let(:from_datetime) { Time.zone.parse("2026-11-01").beginning_of_day }
  let(:boundaries) do
    {
      from_datetime:,
      to_datetime: (from_datetime + 29.days).end_of_day,
      charges_duration: 30
    }
  end

  let(:events_values) { [] }

  def create_event(value:, properties: {})
    Clickhouse::EventsEnriched.create!(
      transaction_id: SecureRandom.uuid,
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      code: billable_metric.code,
      timestamp: from_datetime,
      properties: properties.merge(billable_metric.field_name => value),
      value: value.to_s,
      decimal_value: value.to_d,
      enriched_at: Time.current
    )
  end

  before do
    events_values.each { create_event(value: it, properties: {"region" => "europe"}) }

    event_store.aggregation_property = billable_metric.field_name
    event_store.numeric_property = true
  end

  describe "#query" do
    # The UNION ALL takes the widest type of its branches, so the results alone cannot show a missing cast
    it "casts difference to Decimal256 in every branch of events_data" do
      sql = described_class.new(store: event_store).query

      expect(sql).to include("toDecimal256(:initial_value, 26) as difference")
      expect(sql).to include("toDecimal256(events_enriched.decimal_value, 26) AS difference")
      expect(sql).to include("toDecimal256(0, 26) as difference")
    end

    context "with one event of 1,000,000 held the whole period" do
      let(:events_values) { [1_000_000] }

      it "returns the event value without wrapping" do
        result = event_store.weighted_sum(initial_value: 0)

        # 1e6 x 2,592,000 s / 2,592,000 s; the product 2.592e12 exceeds Decimal(38, 26)
        expect(result.value).to eq(BigDecimal("1000000"))
      end
    end

    # Decimal(38, 26) holds 12 integer digits, so a single event stops below 1e12
    context "with four events of 500,000,000,000 held the whole period" do
      let(:events_values) { Array.new(4, 500_000_000_000) }

      it "returns the running total without wrapping" do
        result = event_store.weighted_sum(initial_value: 0)

        # running total 4 x 5e11 = 2e12 held the whole period
        expect(result.value).to eq(BigDecimal("2000000000000"))
      end
    end

    context "with an initial value of 2,000,000,000,000 and no event" do
      it "returns the initial value without raising" do
        result = event_store.weighted_sum(initial_value: 2_000_000_000_000)

        # initial value 2e12 held the whole period
        expect(result.value).to eq(BigDecimal("2000000000000"))
      end
    end
  end

  describe "#grouped_query" do
    let(:grouped_by) { %w[region] }
    let(:groups) { {"region" => "europe"} }
    let(:initial_values) { [{groups:, value: 0}] }

    # The UNION ALL takes the widest type of its branches, so the results alone cannot show a missing cast
    it "casts difference to Decimal256 in every branch of events_data" do
      sql = described_class.new(store: event_store).grouped_query(initial_values:)

      expect(sql).to include("toDateTime64(:from_datetime, 5, 'UTC'), toDecimal256('0.0', 26))")
      expect(sql).to include("toDecimal256(events_enriched.decimal_value, 26) AS difference")
      expect(sql).to include("toDateTime64(:to_datetime, 5, 'UTC'), toDecimal256(0, 26))")
    end

    context "with one event of 1,000,000 held the whole period" do
      let(:events_values) { [1_000_000] }

      it "returns the event value without wrapping" do
        result = event_store.grouped_weighted_sum(initial_values:)

        expect(result.map(&:groups)).to eq([groups])
        # 1e6 x 2,592,000 s / 2,592,000 s; the product 2.592e12 exceeds Decimal(38, 26)
        expect(result.first.value).to eq(BigDecimal("1000000"))
      end
    end

    # Decimal(38, 26) holds 12 integer digits, so a single event stops below 1e12
    context "with four events of 500,000,000,000 held the whole period" do
      let(:events_values) { Array.new(4, 500_000_000_000) }

      it "returns the running total without wrapping" do
        result = event_store.grouped_weighted_sum(initial_values:)

        expect(result.map(&:groups)).to eq([groups])
        # running total 4 x 5e11 = 2e12 held the whole period
        expect(result.first.value).to eq(BigDecimal("2000000000000"))
      end
    end

    context "with an initial value of 2,000,000,000,000 and no event" do
      let(:initial_values) { [{groups:, value: 2_000_000_000_000}] }

      it "returns the initial value without raising" do
        result = event_store.grouped_weighted_sum(initial_values:)

        expect(result.map(&:groups)).to eq([groups])
        # initial value 2e12 held the whole period
        expect(result.first.value).to eq(BigDecimal("2000000000000"))
      end
    end
  end
end
