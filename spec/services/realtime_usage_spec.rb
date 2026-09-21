# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage do
  describe ".enabled?" do
    subject(:enabled) { described_class.enabled?(organization) }

    let(:organization) do
      create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"])
    end

    include_context "with realtime usage availability"

    it { expect(enabled).to be(true) }

    context "when the organization flag is off" do
      let(:organization) { create(:organization, clickhouse_events_store: true) }

      it { expect(enabled).to be(false) }
    end

    context "when the organization still reads the postgres events store" do
      let(:organization) { create(:organization, feature_flags: ["realtime_usage"]) }

      it "refuses, because the buckets and the postgres events would disagree" do
        expect(enabled).to be(false)
      end
    end

    context "when the kill switch is off" do
      let(:realtime_usage_enabled) { nil }

      it { expect(enabled).to be(false) }
    end

    context "when the kill switch is set to false" do
      let(:realtime_usage_enabled) { "false" }

      it { expect(enabled).to be(false) }
    end

    context "when clickhouse is not available" do
      let(:clickhouse_enabled) { nil }

      it { expect(enabled).to be(false) }
    end

    context "without a premium license" do
      let(:premium_license) { false }

      it { expect(enabled).to be(false) }
    end

    context "with an active store override" do
      it "refuses, so the clickhouse migration keeps comparing two event stores" do
        Events::Stores::StoreFactory.with_override(store_class: Events::Stores::ClickhouseStore, deduplicate: false) do
          expect(described_class.enabled?(organization)).to be(false)
        end
      end
    end
  end

  describe ".deduplicated?" do
    subject(:deduplicated) { described_class.deduplicated?(organization) }

    let(:organization) { create(:organization, clickhouse_events_store: true, clickhouse_deduplication_enabled: true) }

    it { expect(deduplicated).to be(true) }

    context "when the organization reads the postgres store" do
      let(:organization) { create(:organization, clickhouse_deduplication_enabled: true) }

      it { expect(deduplicated).to be(false) }
    end

    context "without deduplication" do
      let(:organization) { create(:organization, clickhouse_events_store: true) }

      it { expect(deduplicated).to be(false) }
    end
  end

  describe ".supported_charge?" do
    subject(:supported) { described_class.supported_charge?(charge) }

    let(:organization) { create(:organization) }
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:charge) { build(:standard_charge, billable_metric:) }

    it "serves a count_agg standard charge" do
      expect(supported).to be(true)
    end

    context "with a sum_agg metric" do
      let(:billable_metric) { create(:sum_billable_metric, organization:) }

      it { expect(supported).to be(true) }
    end

    context "with an aggregation the buckets cannot recompose" do
      let(:billable_metric) { create(:unique_count_billable_metric, organization:) }

      it { expect(supported).to be(false) }
    end

    context "with a percentage charge model" do
      let(:charge) { build(:percentage_charge, billable_metric:) }

      it "is not served, because it walks individual events for running totals" do
        expect(supported).to be(false)
      end
    end

    context "with a graduated charge model" do
      let(:charge) { build(:graduated_charge, billable_metric:) }

      it { expect(supported).to be(true) }
    end

    context "when pay_in_advance" do
      let(:charge) { build(:standard_charge, billable_metric:, pay_in_advance: true) }

      it { expect(supported).to be(false) }
    end

    context "when prorated" do
      let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
      let(:charge) { build(:standard_charge, billable_metric:, prorated: true) }

      it { expect(supported).to be(false) }
    end

    context "with a recurring metric" do
      let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }

      it { expect(supported).to be(false) }
    end

    context "with an expression metric" do
      let(:billable_metric) { create(:sum_billable_metric, organization:, expression: "event.properties.value * 2") }

      it "is not served, because the pipeline does not evaluate expressions yet" do
        expect(supported).to be(false)
      end
    end

    context "with a charge accepting a target wallet" do
      let(:charge) { build(:standard_charge, billable_metric:, accepts_target_wallet: true) }

      it "is not served, because the absent wallet code is not the nil rails emits" do
        expect(supported).to be(false)
      end
    end

    context "with a count_agg charge carrying free units" do
      let(:charge) do
        build(:standard_charge, billable_metric:, properties: {"amount" => "5", "free_units" => 10})
      end

      it "stays served, because count computes its running total in Ruby" do
        expect(supported).to be(true)
      end
    end
  end

  describe "the classification" do
    it "serves only known charge models" do
      expect(Charge::CHARGE_MODELS.map(&:to_s)).to include(*described_class::SUPPORTED_CHARGE_MODELS)
    end

    it "serves only known aggregation types" do
      expect(BillableMetric::AGGREGATION_TYPES.keys.map(&:to_s)).to include(*described_class::SUPPORTED_AGGREGATION_TYPES)
    end

    it "excludes exactly these charge models" do
      excluded = Charge::CHARGE_MODELS.map(&:to_s) - described_class::SUPPORTED_CHARGE_MODELS

      expect(excluded).to match_array(%w[percentage dynamic custom])
    end

    it "excludes exactly these aggregation types" do
      excluded = BillableMetric::AGGREGATION_TYPES.keys.map(&:to_s) - described_class::SUPPORTED_AGGREGATION_TYPES

      expect(excluded).to match_array(%w[max_agg unique_count_agg weighted_sum_agg latest_agg custom_agg])
    end
  end
end
