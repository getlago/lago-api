# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::Clickhouse::AttributedUsageQuery, clickhouse: {clean_before: true} do
  subject(:attributed_usage_query) do
    described_class.new(
      organization_id:,
      external_subscription_id:,
      from_datetime: Time.zone.parse("2026-09-01"),
      to_datetime: Time.zone.parse("2026-09-30 23:59:59"),
      group_key: "team",
      label_filters:,
      charge_columns:,
      limit: 50,
      offset: 0,
      deduplicate:,
      max_groups: 1_000,
      max_execution_time: 10
    )
  end

  let(:organization_id) { SecureRandom.uuid }
  let(:external_subscription_id) { SecureRandom.uuid }
  let(:label_filters) { {} }
  let(:deduplicate) { false }
  let(:tokens_charge_id) { SecureRandom.uuid }
  let(:requests_charge_id) { SecureRandom.uuid }
  let(:opus_filter_id) { SecureRandom.uuid }
  let(:opus_eu_filter_id) { SecureRandom.uuid }
  let(:split) { false }

  let(:tokens_buckets) do
    [
      described_class::PricingBucket.new(
        charge_filter_id: opus_filter_id,
        matching_filters: {"model" => ["opus"]},
        ignored_filters: [{"model" => ["opus"], "region" => ["eu"]}],
        unit_amount_cents: BigDecimal("10")
      ),
      described_class::PricingBucket.new(
        charge_filter_id: opus_eu_filter_id,
        matching_filters: {"model" => ["opus"], "region" => ["eu"]},
        ignored_filters: [],
        unit_amount_cents: BigDecimal("20")
      ),
      described_class::PricingBucket.new(charge_filter_id: nil, matching_filters: {}, ignored_filters: [], unit_amount_cents: BigDecimal("1"))
    ]
  end

  let(:charge_columns) do
    [
      described_class::ChargeColumn.new(charge_id: tokens_charge_id, code: "tokens", count: false, priced: true, split:, buckets: tokens_buckets),
      described_class::ChargeColumn.new(
        charge_id: requests_charge_id,
        code: "requests",
        count: true,
        priced: false,
        split: false,
        buckets: [described_class::PricingBucket.new(charge_filter_id: nil, matching_filters: {}, ignored_filters: [], unit_amount_cents: BigDecimal(0))]
      )
    ]
  end

  def create_event(code:, value:, labels:, properties: {}, timestamp: Time.zone.parse("2026-09-10"), transaction_id: SecureRandom.uuid)
    Clickhouse::EventsEnriched.create!(
      organization_id:,
      external_subscription_id:,
      code:,
      timestamp:,
      transaction_id:,
      properties:,
      attribution_labels: labels,
      value: value.to_s,
      decimal_value: value
    )
  end

  def rows
    Clickhouse::BaseRecord.with_connection { it.select_all(attributed_usage_query.query).rows }
  end

  def cells(row)
    keys, units, amounts, counts = row[1]
    keys.each_with_index.map { |key, index| [key, units[index].to_d, amounts[index].to_d, counts[index].to_i] }.sort
  end

  describe ".column_key" do
    it "joins the charge and the charge filter" do
      expect(described_class.column_key(charge_id: "c1", charge_filter_id: "f1")).to eq("c1|f1")
      expect(described_class.column_key(charge_id: "c1")).to eq("c1|")
    end
  end

  describe ".parse_column_key" do
    it "returns the charge and the charge filter" do
      expect(described_class.parse_column_key("c1|f1")).to eq(["c1", "f1"])
      expect(described_class.parse_column_key("c1|")).to eq(["c1", nil])
    end
  end

  describe "#query" do
    it "guards the query with the ClickHouse limits" do
      expect(attributed_usage_query.query).to include(
        "LIMIT 50 OFFSET 0",
        "max_rows_to_group_by = 1000",
        "group_by_overflow_mode = 'throw'",
        "max_execution_time = 10"
      )
    end

    it "reads the events without FINAL" do
      expect(attributed_usage_query.query).not_to include("FINAL")
    end

    context "with deduplication" do
      let(:deduplicate) { true }

      it "reads the events with FINAL" do
        expect(attributed_usage_query.query).to include("FROM events_enriched FINAL")
      end
    end

    context "with events" do
      before do
        create_event(code: "tokens", value: 100, labels: {"team" => "eng"}, properties: {"model" => "opus"})
        create_event(code: "tokens", value: 10, labels: {"team" => "eng"}, properties: {"model" => "opus", "region" => "eu"})
        create_event(code: "tokens", value: 5, labels: {"team" => "eng"}, properties: {"model" => "haiku"})
        create_event(code: "requests", value: 1, labels: {"team" => "eng"})
        create_event(code: "tokens", value: 7, labels: {"team" => "data"})
        create_event(code: "tokens", value: 3, labels: {})
        create_event(code: "other", value: 1_000, labels: {"team" => "eng"})
        create_event(code: "tokens", value: 1_000, labels: {"team" => "eng"}, timestamp: Time.zone.parse("2026-10-01"))
      end

      it "aggregates each node with its totals" do
        expect(rows.map { |node, _, amount, count, total, total_count, groups| [node, amount.to_d, count, total.to_d, total_count, groups] }).to eq(
          [
            ["", 3, 1, 1_215, 6, 3],
            ["eng", 1_205, 4, 1_215, 6, 3],
            ["data", 7, 1, 1_215, 6, 3]
          ]
        )
      end

      it "sums the units of each charge" do
        expect(cells(rows.second)).to eq(
          [
            ["#{requests_charge_id}|", 1, 0, 1],
            ["#{tokens_charge_id}|", 115, 1_205, 3]
          ].sort
        )
      end

      context "when the charge is split" do
        let(:split) { true }

        it "keys each event with its most specific filter" do
          expect(cells(rows.second)).to eq(
            [
              ["#{requests_charge_id}|", 1, 0, 1],
              ["#{tokens_charge_id}|", 5, 5, 1],
              ["#{tokens_charge_id}|#{opus_filter_id}", 100, 1_000, 1],
              ["#{tokens_charge_id}|#{opus_eu_filter_id}", 10, 200, 1]
            ].sort
          )
        end
      end

      context "with label filters" do
        let(:label_filters) { {"team" => ["data", ""]} }

        it "keeps the matching events only" do
          expect(rows.map(&:first)).to eq(["", "data"])
        end
      end
    end
  end
end
