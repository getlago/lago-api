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
      order_by:,
      search:,
      limit:,
      offset: 0,
      deduplicate:,
      max_groups: 1_000,
      max_execution_time: 10
    )
  end

  let(:organization_id) { SecureRandom.uuid }
  let(:external_subscription_id) { SecureRandom.uuid }
  let(:label_filters) { {} }
  let(:order_by) { "amount" }
  let(:search) { nil }
  let(:limit) { 50 }
  let(:deduplicate) { false }
  let(:tokens_charge_id) { SecureRandom.uuid }
  let(:requests_charge_id) { SecureRandom.uuid }
  let(:opus_eu_filter_id) { SecureRandom.uuid }
  let(:opus_filter_id) { SecureRandom.uuid }
  let(:split) { false }

  # Ranked by specificity: {model, region} before {model}. Rank 3 is the charge's own price.
  let(:tokens_lookup) do
    UsageAttributions::ChargePriceLookupService::Lookup.new(
      key_sets: [[%w[model region], {"opus\u001Feu" => 1}], [%w[model], {"opus" => 2}]],
      filter_ids: [opus_eu_filter_id, opus_filter_id],
      unit_amounts_cents: [BigDecimal(20), BigDecimal(10)]
    )
  end

  let(:charge_columns) do
    [
      described_class::ChargeColumn.new(
        charge_id: tokens_charge_id, code: "tokens", count: false, unit_amount_cents: BigDecimal(1), lookup: tokens_lookup, split:
      ),
      described_class::ChargeColumn.new(
        charge_id: requests_charge_id, code: "requests", count: true, unit_amount_cents: nil, lookup: nil, split: false
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

  def row(node)
    attributed_usage_query.rows.find { it["node"] == node }
  end

  def cells(row)
    attributed_usage_query.cells.each_index.map do |index|
      [row["units_#{index}"].to_d, row["amount_#{index}"].to_d, row["events_#{index}"].to_i]
    end
  end

  describe "#cells" do
    it "returns one cell per charge" do
      expect(attributed_usage_query.cells.map { [it.charge_id, it.charge_filter_id, it.priced] }).to eq(
        [[tokens_charge_id, nil, true], [requests_charge_id, nil, false]]
      )
    end

    context "when the charge is split" do
      let(:split) { true }

      it "returns one cell per filter and one for the default price" do
        expect(attributed_usage_query.cells.map { [it.charge_id, it.charge_filter_id, it.rank] }).to eq(
          [
            [tokens_charge_id, opus_eu_filter_id, 1],
            [tokens_charge_id, opus_filter_id, 2],
            [tokens_charge_id, nil, 3],
            [requests_charge_id, nil, nil]
          ]
        )
      end
    end
  end

  describe "#query" do
    it "guards the query with the ClickHouse limits" do
      expect(attributed_usage_query.query).to include(
        "max_rows_to_group_by = 1000",
        "group_by_overflow_mode = 'throw'",
        "max_execution_time = 10",
        "timeout_overflow_mode = 'throw'"
      )
    end

    it "groups the events by the attribution value only" do
      expect(attributed_usage_query.query).to include("GROUP BY node )")
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
  end

  describe "#rows" do
    before do
      create_event(code: "tokens", value: 100, labels: {"team" => "eng"}, properties: {"model" => "opus"})
      create_event(code: "tokens", value: 10, labels: {"team" => "eng"}, properties: {"model" => "opus", "region" => "eu"})
      create_event(code: "tokens", value: 5, labels: {"team" => "eng"}, properties: {"model" => "haiku"})
      create_event(code: "requests", value: 1, labels: {"team" => "eng"})
      create_event(code: "requests", value: 1, labels: {"team" => "data"})
      create_event(code: "requests", value: 1, labels: {"team" => "data"})
      create_event(code: "tokens", value: 7, labels: {"team" => "data"})
      create_event(code: "tokens", value: 3, labels: {})
      create_event(code: "other", value: 1_000, labels: {"team" => "eng"})
      create_event(code: "tokens", value: 1_000, labels: {"team" => "eng"}, timestamp: Time.zone.parse("2026-10-01"))
    end

    it "ranks the attributed values, with the unattributed usage apart" do
      expect(attributed_usage_query.rows.map { [it["node"], it["rank"].to_i, it["in_page"].to_i, it["amount"].to_d, it["events"].to_i] }).to eq(
        [
          ["eng", 1, 1, 1_205, 4],
          ["data", 2, 1, 7, 3],
          ["", 1, 0, 3, 1]
        ]
      )
    end

    it "prices each event with its most specific filter" do
      expect(cells(row("eng"))).to eq([[115, 1_205, 3], [1, 0, 1]])
    end

    it "returns the totals of the attributed values" do
      expect([row("eng")["groups_count"].to_i, row("eng")["total_amount"].to_d, row("eng")["total_events"].to_i]).to eq([2, 1_212, 7])
      expect(row("eng").keys.grep(/running/)).to eq([])
    end

    context "when the charge is split" do
      let(:split) { true }

      it "sums each filter in its own cell" do
        expect(cells(row("eng"))).to eq([[10, 200, 1], [100, 1_000, 1], [5, 5, 1], [1, 0, 1]])
      end
    end

    context "when ordered by events count" do
      let(:order_by) { "events_count" }

      it "ranks the values by their events" do
        expect(attributed_usage_query.rows.map { [it["node"], it["rank"].to_i] }).to eq([["eng", 1], ["data", 2], ["", 1]])
      end
    end

    context "with a page smaller than the level" do
      let(:limit) { 1 }
      let(:order_by) { "events_count" }

      it "returns the page, the first row and the unattributed usage" do
        expect(attributed_usage_query.rows.map { [it["node"], it["in_page"].to_i] }).to eq([["eng", 1], ["", 0]])
      end
    end

    context "with a search" do
      let(:search) { "DAT" }

      it "returns the matching values with their rank in the level" do
        expect(attributed_usage_query.rows.map { [it["node"], it["rank"].to_i, it["in_page"].to_i] }).to eq(
          [["eng", 1, 0], ["data", 2, 1], ["", 1, 0]]
        )
      end
    end

    context "with label filters" do
      let(:label_filters) { {"team" => ["data", ""]} }

      it "keeps the matching events only" do
        expect(attributed_usage_query.rows.map { it["node"] }).to eq(["data", ""])
      end
    end

    context "with values holding quotes and backslashes" do
      let(:tricky_team) { "o\\'brien" }

      before { create_event(code: "tokens", value: 1, labels: {"team" => tricky_team}) }

      context "with a label filter" do
        let(:label_filters) { {"team" => [tricky_team]} }

        it "matches the value as a plain string" do
          expect(attributed_usage_query.rows.map { it["node"] }).to eq([tricky_team])
        end
      end

      context "with a search" do
        let(:search) { "\\' OR 1=1 OR '" }

        it "searches for the value as a plain string" do
          expect(attributed_usage_query.rows.select { it["in_page"].to_i == 1 }).to eq([])
        end
      end
    end

    context "with a lookup past the ClickHouse parser defaults" do
      let(:tokens_lookup) do
        entries = Array.new(20_000) { |index| ["model-#{index.to_s.rjust(12, "0")}", index + 1] }.to_h.merge("opus" => 20_001)

        UsageAttributions::ChargePriceLookupService::Lookup.new(
          key_sets: [[%w[model], entries]],
          filter_ids: Array.new(20_001) { SecureRandom.uuid },
          unit_amounts_cents: Array.new(20_000) { BigDecimal(0) } + [BigDecimal(10)]
        )
      end

      it "runs the statement with the parser limits raised" do
        expect(attributed_usage_query.query.bytesize).to be > 262_144
        expect(cells(row("eng"))).to eq([[115, 1_105, 3], [1, 0, 1]])
      end
    end
  end
end
