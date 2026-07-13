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

  # The following contexts cover edge cases with empty filters, subset
  # children, and duplicate filters. Empty filters should not occur in normal
  # usage but missing validations allow them in production; the store-level
  # defensive guards (ISSUE-1799) prevent them from producing invalid SQL.
  # Strict-subset children are kept verbatim in ignored_filters so their
  # events are excluded from the parent's bucket instead of being counted in
  # both buckets. Identical children are resolved with a tie-break on
  # [created_at, id]: only the oldest duplicate counts the events, the others
  # keep the older duplicate in their ignored_filters and count zero.

  context "when a filter has no values" do
    subject(:service_result) { described_class.call(charge: isolated_charge, filter: current_filter) }

    let(:isolated_charge) { create(:standard_charge, billable_metric:) }

    let(:empty_a) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "empty_a", created_at: 2.days.ago) }
    let(:empty_b) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "empty_b", created_at: 1.day.ago) }
    let(:with_values) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "with_values") }

    before do
      empty_a
      empty_b
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: with_values)
    end

    describe "for empty_a" do
      let(:current_filter) { empty_a }

      # empty_a and empty_b are vacuously identical (both match {}), so the
      # tie-break applies: empty_a is older and drops empty_b's {} entry.
      it "does not include the newer empty filter in ignored_filters" do
        expect(service_result.matching_filters).to eq({})
        expect(service_result.ignored_filters).to eq(
          [
            {"size" => ["512"]}
          ]
        )
      end
    end

    describe "for with_values" do
      let(:current_filter) { with_values }

      it "does not include empty filters as children" do
        expect(service_result.matching_filters).to eq({"size" => ["512"]})
        expect(service_result.ignored_filters).to eq([])
      end
    end
  end

  context "when a child's values are a subset of the parent's" do
    subject(:service_result) { described_class.call(charge: isolated_charge, filter: current_filter) }

    let(:isolated_charge) { create(:standard_charge, billable_metric:) }

    let(:parent_filter) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "parent") }
    let(:subset_child) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "subset_child") }
    let(:partial_overlap) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "partial") }

    before do
      create(:charge_filter_value, values: %w[512 1024], billable_metric_filter: filter_size, charge_filter: parent_filter)
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: subset_child)
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: partial_overlap)
      create(:charge_filter_value, values: ["25"], billable_metric_filter: filter_steps, charge_filter: partial_overlap)
    end

    describe "for parent_filter" do
      let(:current_filter) { parent_filter }

      it "keeps the subset child verbatim and keeps different-key children intact" do
        expect(service_result.matching_filters).to eq({"size" => %w[512 1024]})
        expect(service_result.ignored_filters).to eq(
          [
            {"size" => ["512"]},
            {"size" => ["512"], "steps" => ["25"]}
          ]
        )
      end
    end
  end

  context "when a child is a subset on one key but not on another" do
    subject(:service_result) { described_class.call(charge: isolated_charge, filter: current_filter) }

    let(:isolated_charge) { create(:standard_charge, billable_metric:) }

    let(:parent_filter) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "parent") }
    let(:mixed_child) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "mixed_child") }

    before do
      create(:charge_filter_value, values: %w[512 1024], billable_metric_filter: filter_size, charge_filter: parent_filter)
      create(:charge_filter_value, values: %w[25 50], billable_metric_filter: filter_steps, charge_filter: parent_filter)
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: mixed_child)
      create(:charge_filter_value, values: %w[25 75], billable_metric_filter: filter_steps, charge_filter: mixed_child)
    end

    describe "for parent_filter" do
      let(:current_filter) { parent_filter }

      it "subtracts the matching values from the non-subset child" do
        expect(service_result.matching_filters).to eq({"size" => %w[512 1024], "steps" => %w[25 50]})
        expect(service_result.ignored_filters).to eq(
          [{"size" => [], "steps" => ["75"]}]
        )
      end
    end
  end

  # Identical duplicates are resolved with a tie-break on [created_at, id]:
  # the oldest duplicate drops the newer ones from its ignored_filters and
  # counts the events; the newer ones keep at least one older identical
  # sibling verbatim and count zero.
  context "when filters have identical keys and values" do
    subject(:service_result) { described_class.call(charge: isolated_charge, filter: current_filter) }

    let(:isolated_charge) { create(:standard_charge, billable_metric:) }

    let(:filter_a) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "filter_a", created_at: 3.days.ago) }
    let(:filter_b) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "filter_b", created_at: 2.days.ago) }
    let(:filter_c) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "filter_c", created_at: 1.day.ago) }

    before do
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: filter_a)
      create(:charge_filter_value, values: ["25"], billable_metric_filter: filter_steps, charge_filter: filter_a)
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: filter_b)
      create(:charge_filter_value, values: ["25"], billable_metric_filter: filter_steps, charge_filter: filter_b)
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: filter_c)
      create(:charge_filter_value, values: ["25"], billable_metric_filter: filter_steps, charge_filter: filter_c)
    end

    describe "for filter_a (oldest)" do
      let(:current_filter) { filter_a }

      it "drops the newer identical siblings from ignored_filters" do
        expect(service_result.matching_filters).to eq({"size" => ["512"], "steps" => ["25"]})
        expect(service_result.ignored_filters).to eq([])
      end
    end

    describe "for filter_b (middle)" do
      let(:current_filter) { filter_b }

      it "keeps only the older identical sibling verbatim" do
        expect(service_result.matching_filters).to eq({"size" => ["512"], "steps" => ["25"]})
        expect(service_result.ignored_filters).to eq(
          [{"size" => ["512"], "steps" => ["25"]}]
        )
      end
    end

    describe "for filter_c (newest)" do
      let(:current_filter) { filter_c }

      it "keeps both older identical siblings verbatim" do
        expect(service_result.matching_filters).to eq({"size" => ["512"], "steps" => ["25"]})
        expect(service_result.ignored_filters).to eq(
          [
            {"size" => ["512"], "steps" => ["25"]},
            {"size" => ["512"], "steps" => ["25"]}
          ]
        )
      end
    end
  end

  # to_h_with_all_values orders keys by the values' updated_at (ChargeFilterValue
  # default scope), so two filters with the same keys can enumerate them in a
  # different order. The identical/subset logic must compare keys
  # order-independently; otherwise the same-keys branch is skipped and the older
  # parent wrongly excludes the identical duplicate's events, counting zero.
  context "when an identical child enumerates its keys in a different order" do
    subject(:service_result) { described_class.call(charge: isolated_charge, filter: current_filter) }

    let(:isolated_charge) { create(:standard_charge, billable_metric:) }
    let(:parent_filter) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "parent", created_at: 2.days.ago) }
    let(:duplicate) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "duplicate", created_at: 1.day.ago) }

    before do
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: parent_filter, updated_at: 2.days.ago)
      create(:charge_filter_value, values: ["25"], billable_metric_filter: filter_steps, charge_filter: parent_filter, updated_at: 1.day.ago)
      # Reversed order: steps is updated before size, so the duplicate enumerates
      # its keys as [steps, size] while the parent enumerates them as [size, steps].
      create(:charge_filter_value, values: ["25"], billable_metric_filter: filter_steps, charge_filter: duplicate, updated_at: 2.days.ago)
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: duplicate, updated_at: 1.day.ago)
    end

    describe "for the older parent" do
      let(:current_filter) { parent_filter }

      it "recognizes the reordered duplicate and drops it from ignored_filters" do
        expect(service_result.matching_filters).to eq({"size" => ["512"], "steps" => ["25"]})
        expect(service_result.ignored_filters).to eq([])
      end
    end
  end

  # When identical duplicates share the same created_at, the id part of the
  # [created_at, id] tie-break decides: exactly one filter counts the events.
  context "when identical filters share the same created_at" do
    subject(:service_result) { described_class.call(charge: isolated_charge, filter: current_filter) }

    let(:isolated_charge) { create(:standard_charge, billable_metric:) }
    let(:created_at) { 1.day.ago }

    let(:filter_a) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "filter_a", created_at:) }
    let(:filter_b) { create(:charge_filter, charge: isolated_charge, invoice_display_name: "filter_b", created_at:) }

    let(:winner) { [filter_a, filter_b].min_by(&:id) }
    let(:loser) { [filter_a, filter_b].max_by(&:id) }

    before do
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: filter_a)
      create(:charge_filter_value, values: ["512"], billable_metric_filter: filter_size, charge_filter: filter_b)
    end

    describe "for the filter with the lowest id" do
      let(:current_filter) { winner }

      it "drops the identical sibling from ignored_filters" do
        expect(service_result.matching_filters).to eq({"size" => ["512"]})
        expect(service_result.ignored_filters).to eq([])
      end
    end

    describe "for the filter with the highest id" do
      let(:current_filter) { loser }

      it "keeps the identical sibling verbatim" do
        expect(service_result.matching_filters).to eq({"size" => ["512"]})
        expect(service_result.ignored_filters).to eq(
          [{"size" => ["512"]}]
        )
      end
    end
  end
end
