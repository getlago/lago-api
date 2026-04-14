# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeFilters::MatchingAndIgnoredService do
  subject(:service_result) { described_class.call(charge:, filter: current_filter) }

  let(:billable_metric) { create(:billable_metric) }
  let(:charge) { create(:standard_charge, billable_metric:) }

  let(:filter_steps) { create(:billable_metric_filter, billable_metric:, key: "steps", values: %w[25 50 75 100]) }
  let(:filter_size) { create(:billable_metric_filter, billable_metric:, key: "size", values: %w[512 1024]) }
  let(:filter_model) do
    create(:billable_metric_filter, billable_metric:, key: "model", values: %w[llama-1 llama-2 llama-3 llama-4])
  end

  let(:f1) { create(:charge_filter, charge:, invoice_display_name: "f1") }
  let(:f1_values) do
    [
      create(:charge_filter_value, values: ["25"], billable_metric_filter: filter_steps, charge_filter: f1),
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: f1),
      create(:charge_filter_value, values: ["llama-2"], billable_metric_filter: filter_model, charge_filter: f1)
    ]
  end

  let(:f2) { create(:charge_filter, charge:, invoice_display_name: "f2") }
  let(:f2_values) do
    [
      create(:charge_filter_value, values: ["25"], billable_metric_filter: filter_steps, charge_filter: f2),
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: f2)
    ]
  end

  let(:f3) { create(:charge_filter, charge:, invoice_display_name: "f3") }
  let(:f3_values) do
    [
      create(
        :charge_filter_value,
        values: [ChargeFilterValue::ALL_FILTER_VALUES],
        billable_metric_filter: filter_steps,
        charge_filter: f3
      ),
      create(
        :charge_filter_value,
        values: [ChargeFilterValue::ALL_FILTER_VALUES],
        billable_metric_filter: filter_size,
        charge_filter: f3
      )
    ]
  end

  let(:f4) { create(:charge_filter, charge:, invoice_display_name: "f4") }
  let(:f4_values) do
    [
      create(
        :charge_filter_value,
        values: [ChargeFilterValue::ALL_FILTER_VALUES],
        billable_metric_filter: filter_size,
        charge_filter: f4
      )
    ]
  end

  let(:f5) { create(:charge_filter, charge:, invoice_display_name: "f5") }
  let(:f5_values) do
    [
      create(
        :charge_filter_value,
        values: ["512"],
        billable_metric_filter: filter_size,
        charge_filter: f5
      )
    ]
  end

  let(:f6) { create(:charge_filter, charge:, invoice_display_name: "f6") }
  before do
    f1
    f1_values
    f2
    f2_values
    f3
    f3_values
    f4
    f4_values
    f5
    f5_values
    f6
  end

  describe "for f1" do
    let(:current_filter) { f1 }

    it "returns a formatted hash" do
      expect(service_result.matching_filters).to eq({"size" => %w[512], "steps" => %w[25], "model" => %w[llama-2]})
      expect(service_result.ignored_filters).to eq([])
    end
  end

  describe "for f2" do
    let(:current_filter) { f2 }

    it "returns a formatted hash" do
      expect(service_result.matching_filters).to eq({"size" => %w[512], "steps" => %w[25]})
      expect(service_result.ignored_filters).to eq(
        [
          {"model" => %w[llama-2], "size" => %w[512], "steps" => %w[25]},
          {"size" => ["1024"], "steps" => %w[50 75 100]}
        ]
      )
    end
  end

  describe "for f3" do
    let(:current_filter) { f3 }

    it "returns a formatted hash" do
      expect(service_result.matching_filters).to eq({"size" => %w[512 1024], "steps" => %w[25 50 75 100]})
      expect(service_result.ignored_filters).to eq(
        [
          {"model" => ["llama-2"], "size" => ["512"], "steps" => ["25"]},
          {"size" => ["512"], "steps" => ["25"]}
        ]
      )
    end
  end

  describe "for f4" do
    let(:current_filter) { f4 }

    it "returns a formatted hash" do
      expect(service_result.matching_filters).to eq({"size" => %w[512 1024]})
      expect(service_result.ignored_filters).to eq(
        [
          {"model" => ["llama-2"], "size" => ["512"], "steps" => ["25"]},
          {"size" => ["512"], "steps" => ["25"]},
          {"size" => %w[512 1024], "steps" => %w[25 50 75 100]},
          {"size" => ["512"]}
        ]
      )
    end
  end

  describe "for f5" do
    let(:current_filter) { f5 }

    it "returns a formatted hash" do
      expect(service_result.matching_filters).to eq({"size" => %w[512]})
      expect(service_result.ignored_filters).to eq(
        [
          {"model" => ["llama-2"], "size" => ["512"], "steps" => ["25"]},
          {"size" => ["512"], "steps" => ["25"]},
          {"size" => %w[512 1024], "steps" => %w[25 50 75 100]},
          {"size" => ["1024"]}
        ]
      )
    end
  end

  describe "for f6 (filter with no values)" do
    let(:current_filter) { f6 }

    it "returns a formatted hash" do
      expect(service_result.matching_filters).to eq({})
      expect(service_result.ignored_filters).to match_array(
        [
          {"size" => ["512"], "steps" => ["25"], "model" => ["llama-2"]},
          {"size" => ["512"], "steps" => ["25"]},
          {"size" => ["512", "1024"], "steps" => ["25", "50", "75", "100"]},
          {"size" => ["512", "1024"]},
          {"size" => ["512"]}
        ]
      )
    end
  end

  describe "when a child filter has all values subsumed by the current filter" do
    subject(:service_result) { described_class.call(charge: charge_2, filter: current_filter) }

    let(:billable_metric_2) { create(:billable_metric) }
    let(:charge_2) { create(:standard_charge, billable_metric: billable_metric_2) }

    let(:bm_filter_region) { create(:billable_metric_filter, billable_metric: billable_metric_2, key: "region", values: %w[eu us]) }
    let(:bm_filter_cloud) { create(:billable_metric_filter, billable_metric: billable_metric_2, key: "cloud", values: %w[aws gcp]) }

    # parent_filter has region=eu and cloud=aws (fewer values)
    let(:parent_filter) { create(:charge_filter, charge: charge_2, invoice_display_name: "parent") }
    let(:parent_filter_values) do
      [
        create(:charge_filter_value, values: %w[eu], billable_metric_filter: bm_filter_region, charge_filter: parent_filter),
        create(:charge_filter_value, values: %w[aws], billable_metric_filter: bm_filter_cloud, charge_filter: parent_filter)
      ]
    end

    # superset_child has region=eu,us and cloud=aws,gcp (superset of parent).
    # After subtraction (child_values - parent_values): {"region" => ["us"], "cloud" => ["gcp"]} (non-empty, kept).
    let(:superset_child) { create(:charge_filter, charge: charge_2, invoice_display_name: "superset") }
    let(:superset_child_values) do
      [
        create(:charge_filter_value, values: %w[eu us], billable_metric_filter: bm_filter_region, charge_filter: superset_child),
        create(:charge_filter_value, values: %w[aws gcp], billable_metric_filter: bm_filter_cloud, charge_filter: superset_child)
      ]
    end

    # identical_child has the exact same keys and values as parent_filter.
    # After subtraction: {"region" => [], "cloud" => []} (all empty, must be rejected).
    let(:identical_child) { create(:charge_filter, charge: charge_2, invoice_display_name: "identical") }
    let(:identical_child_values) do
      [
        create(:charge_filter_value, values: %w[eu], billable_metric_filter: bm_filter_region, charge_filter: identical_child),
        create(:charge_filter_value, values: %w[aws], billable_metric_filter: bm_filter_cloud, charge_filter: identical_child)
      ]
    end

    let(:current_filter) { parent_filter }

    before do
      parent_filter_values
      superset_child_values
      identical_child_values
    end

    it "rejects ignored filters where all values are empty arrays after subtraction" do
      # superset_child: {"region" => ["eu", "us"], "cloud" => ["aws", "gcp"]} - parent → {"region" => ["us"], "cloud" => ["gcp"]} (kept)
      # identical_child: {"region" => ["eu"], "cloud" => ["aws"]} - parent → {"region" => [], "cloud" => []} (rejected)
      expect(service_result.ignored_filters).to eq(
        [{"region" => %w[us], "cloud" => %w[gcp]}]
      )
    end
  end
end
