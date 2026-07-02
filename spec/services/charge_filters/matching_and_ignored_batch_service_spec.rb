# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeFilters::MatchingAndIgnoredBatchService do
  subject(:service_result) { described_class.call(charge:) }

  let(:billable_metric) { create(:billable_metric) }
  let(:charge) { create(:standard_charge, billable_metric:) }

  let(:filter_steps) { create(:billable_metric_filter, billable_metric:, key: "steps", values: %w[25 50 75 100]) }
  let(:filter_size) { create(:billable_metric_filter, billable_metric:, key: "size", values: %w[512 1024]) }
  let(:filter_model) do
    create(:billable_metric_filter, billable_metric:, key: "model", values: %w[llama-1 llama-2 llama-3 llama-4])
  end

  let(:f1) { create(:charge_filter, charge:, invoice_display_name: "f1") }
  let(:f2) { create(:charge_filter, charge:, invoice_display_name: "f2") }
  let(:f3) { create(:charge_filter, charge:, invoice_display_name: "f3") }
  let(:f4) { create(:charge_filter, charge:, invoice_display_name: "f4") }
  let(:f5) { create(:charge_filter, charge:, invoice_display_name: "f5") }

  before do
    create(:charge_filter_value, values: ["25"], billable_metric_filter: filter_steps, charge_filter: f1)
    create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: f1)
    create(:charge_filter_value, values: ["llama-2"], billable_metric_filter: filter_model, charge_filter: f1)

    create(:charge_filter_value, values: ["25"], billable_metric_filter: filter_steps, charge_filter: f2)
    create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: f2)

    create(:charge_filter_value, values: [ChargeFilterValue::ALL_FILTER_VALUES], billable_metric_filter: filter_steps, charge_filter: f3)
    create(:charge_filter_value, values: [ChargeFilterValue::ALL_FILTER_VALUES], billable_metric_filter: filter_size, charge_filter: f3)

    create(:charge_filter_value, values: [ChargeFilterValue::ALL_FILTER_VALUES], billable_metric_filter: filter_size, charge_filter: f4)

    create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: f5)
  end

  it "returns the matching and ignored filters for every filter of the charge" do
    filters_results = service_result.filters_results

    expect(filters_results.keys).to match_array([f1.id, f2.id, f3.id, f4.id, f5.id])

    expect(filters_results[f1.id]).to eq(
      matching_filters: {"size" => %w[512], "steps" => %w[25], "model" => %w[llama-2]},
      ignored_filters: []
    )

    expect(filters_results[f2.id]).to eq(
      matching_filters: {"size" => %w[512], "steps" => %w[25]},
      ignored_filters: [
        {"model" => %w[llama-2], "size" => %w[512], "steps" => %w[25]},
        {"size" => ["1024"], "steps" => %w[50 75 100]}
      ]
    )

    expect(filters_results[f3.id]).to eq(
      matching_filters: {"size" => %w[512 1024], "steps" => %w[25 50 75 100]},
      ignored_filters: [
        {"model" => ["llama-2"], "size" => ["512"], "steps" => ["25"]},
        {"size" => ["512"], "steps" => ["25"]}
      ]
    )

    expect(filters_results[f4.id]).to eq(
      matching_filters: {"size" => %w[512 1024]},
      ignored_filters: [
        {"model" => ["llama-2"], "size" => ["512"], "steps" => ["25"]},
        {"size" => ["512"], "steps" => ["25"]},
        {"size" => %w[512 1024], "steps" => %w[25 50 75 100]},
        {"size" => ["512"]}
      ]
    )

    expect(filters_results[f5.id]).to eq(
      matching_filters: {"size" => %w[512]},
      ignored_filters: [
        {"model" => ["llama-2"], "size" => ["512"], "steps" => ["25"]},
        {"size" => ["512"], "steps" => ["25"]},
        {"size" => %w[512 1024], "steps" => %w[25 50 75 100]},
        {"size" => ["1024"]}
      ]
    )
  end

  it "returns the same results as the per-filter service" do
    filters_results = service_result.filters_results

    charge.filters.each do |filter|
      per_filter = ChargeFilters::MatchingAndIgnoredService.call(charge:, filter:)

      expect(filters_results[filter.id][:matching_filters]).to eq(per_filter.matching_filters)
      expect(filters_results[filter.id][:ignored_filters]).to eq(per_filter.ignored_filters)
    end
  end

  context "when the charge has no filters" do
    let(:isolated_charge) { create(:standard_charge, billable_metric:) }

    it "returns an empty hash" do
      result = described_class.call(charge: isolated_charge)

      expect(result.filters_results).to eq({})
    end
  end

  context "when some filters have no values" do
    subject(:service_result) { described_class.call(charge: isolated_charge) }

    let(:isolated_charge) { create(:standard_charge, billable_metric:) }

    let(:empty_a) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "empty_a") }
    let(:empty_b) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "empty_b") }
    let(:with_values) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "with_values") }

    before do
      empty_a
      empty_b
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: with_values)
    end

    it "matches all siblings for empty filters and excludes them from the other filters" do
      filters_results = service_result.filters_results

      expect(filters_results[empty_a.id]).to eq(
        matching_filters: {},
        ignored_filters: [
          {},
          {"size" => ["512"]}
        ]
      )

      expect(filters_results[with_values.id]).to eq(
        matching_filters: {"size" => ["512"]},
        ignored_filters: []
      )
    end

    it "returns the same results as the per-filter service" do
      filters_results = service_result.filters_results

      isolated_charge.filters.each do |filter|
        per_filter = ChargeFilters::MatchingAndIgnoredService.call(charge: isolated_charge, filter:)

        expect(filters_results[filter.id][:matching_filters]).to eq(per_filter.matching_filters)
        expect(filters_results[filter.id][:ignored_filters]).to eq(per_filter.ignored_filters)
      end
    end
  end

  context "with subset and identical filters" do
    subject(:service_result) { described_class.call(charge: isolated_charge) }

    let(:isolated_charge) { create(:standard_charge, billable_metric:) }

    let(:parent_filter) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "parent") }
    let(:subset_child) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "subset_child") }
    let(:partial_overlap) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "partial") }
    let(:twin_a) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "twin_a") }
    let(:twin_b) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "twin_b") }

    before do
      create(:charge_filter_value, values: %w[512 1024], billable_metric_filter: filter_size, charge_filter: parent_filter)
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: subset_child)
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: partial_overlap)
      create(:charge_filter_value, values: ["25"], billable_metric_filter: filter_steps, charge_filter: partial_overlap)
      create(:charge_filter_value, values: ["llama-1"], billable_metric_filter: filter_model, charge_filter: twin_a)
      create(:charge_filter_value, values: ["llama-1"], billable_metric_filter: filter_model, charge_filter: twin_b)
    end

    it "returns the same results as the per-filter service" do
      filters_results = service_result.filters_results

      isolated_charge.filters.each do |filter|
        per_filter = ChargeFilters::MatchingAndIgnoredService.call(charge: isolated_charge, filter:)

        expect(filters_results[filter.id][:matching_filters]).to eq(per_filter.matching_filters)
        expect(filters_results[filter.id][:ignored_filters]).to eq(per_filter.ignored_filters)
      end
    end
  end
end
