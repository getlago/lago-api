# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::BillingPeriodFilters::MatchingAndIgnoredService do
  subject(:service_result) { described_class.call(target_filter:) }

  let(:billable_metric) { create(:billable_metric) }
  let(:organization) { billable_metric.organization }
  let(:target_filter) { build_target(current_filter) }
  let(:size_filter) { create(:billable_metric_filter, billable_metric:, key: "size", values: %w[512 1024]) }
  let(:steps_filter) { create(:billable_metric_filter, billable_metric:, key: "steps", values: %w[25 50 75 100]) }
  let(:model_filter) do
    create(:billable_metric_filter, billable_metric:, key: "model", values: %w[llama-1 llama-2 llama-3 llama-4])
  end

  def count_queries(tables)
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
      queries << payload[:sql] if tables.any? { |table| payload[:sql].include?(%("#{table}")) }
    end
    yield
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  shared_examples "matching and ignored filters" do
    context "with a multi-key hierarchy" do
      let(:f1) { create_filter }
      let(:f2) { create_filter }
      let(:f3) { create_filter }
      let(:f4) { create_filter }
      let(:f5) { create_filter }

      before do
        create_filter_values(f1, steps_filter, ["25"])
        create_filter_values(f1, size_filter, ["512"])
        create_filter_values(f1, model_filter, ["llama-2"])
        create_filter_values(f2, steps_filter, ["25"])
        create_filter_values(f2, size_filter, ["512"])
        create_filter_values(f3, steps_filter, nil)
        create_filter_values(f3, size_filter, nil)
        create_filter_values(f4, size_filter, nil)
        create_filter_values(f5, size_filter, ["512"])
      end

      context "when selecting f1" do
        let(:current_filter) { f1 }

        it "matches all three keys without ignored children" do
          expect(service_result.matching_filters).to eq({"size" => ["512"], "steps" => ["25"], "model" => ["llama-2"]})
          expect(service_result.ignored_filters).to eq([])
        end
      end

      context "when selecting f2" do
        let(:current_filter) { f2 }

        it "keeps the more specific child and subtracts matching values from the all-values sibling" do
          expect(service_result.matching_filters).to eq({"size" => ["512"], "steps" => ["25"]})
          expect(service_result.ignored_filters).to eq([
            {"model" => ["llama-2"], "size" => ["512"], "steps" => ["25"]},
            {"size" => ["1024"], "steps" => %w[50 75 100]}
          ])
        end
      end

      context "when selecting f3" do
        let(:current_filter) { f3 }

        it "expands all configured values on both keys and keeps explicit children" do
          expect(service_result.matching_filters).to eq({"size" => %w[512 1024], "steps" => %w[25 50 75 100]})
          expect(service_result.ignored_filters).to eq([
            {"model" => ["llama-2"], "size" => ["512"], "steps" => ["25"]},
            {"size" => ["512"], "steps" => ["25"]}
          ])
        end
      end

      context "when selecting f4" do
        let(:current_filter) { f4 }

        it "expands all configured values and ignores all more specific filters" do
          expect(service_result.matching_filters).to eq({"size" => %w[512 1024]})
          expect(service_result.ignored_filters).to eq([
            {"model" => ["llama-2"], "size" => ["512"], "steps" => ["25"]},
            {"size" => ["512"], "steps" => ["25"]},
            {"size" => %w[512 1024], "steps" => %w[25 50 75 100]},
            {"size" => ["512"]}
          ])
        end
      end

      context "when selecting f5" do
        let(:current_filter) { f5 }

        it "keeps different-key children and subtracts its value from the all-values sibling" do
          expect(service_result.matching_filters).to eq({"size" => ["512"]})
          expect(service_result.ignored_filters).to eq([
            {"model" => ["llama-2"], "size" => ["512"], "steps" => ["25"]},
            {"size" => ["512"], "steps" => ["25"]},
            {"size" => %w[512 1024], "steps" => %w[25 50 75 100]},
            {"size" => ["1024"]}
          ])
        end
      end

      describe "filters loading" do
        let(:current_filter) { f1 }
        let(:preload) { false }
        let(:target_filter) { build_target(current_filter, reload: true, preload:) }

        before do
          target_filter
          # Exclude the caller-provided filter's own value queries from the count.
          current_filter.to_h_with_all_values
        end

        it "eager loads filters, values and metric filters in three queries" do
          expect(count_queries(filter_tables) { service_result }.size).to eq(3)
        end

        context "when fully preloaded" do
          let(:preload) { true }

          it "reuses the loaded associations without filter queries" do
            expect(count_queries(filter_tables) { service_result }).to eq([])
            expect(service_result.matching_filters).to eq({"size" => ["512"], "steps" => ["25"], "model" => ["llama-2"]})
            expect(service_result.ignored_filters).to eq([])
          end
        end
      end
    end

    context "when filters have no values" do
      let(:empty_a) { create_filter(created_at: 2.days.ago) }
      let(:empty_b) { create_filter(created_at: 1.day.ago) }
      let(:with_values) { create_filter }

      before do
        empty_a
        empty_b
        create_filter_values(with_values, size_filter, ["512"])
      end

      context "when selecting the older empty filter" do
        let(:current_filter) { empty_a }

        it "drops the newer empty duplicate but keeps the explicit-valued child" do
          expect(service_result.matching_filters).to eq({})
          expect(service_result.ignored_filters).to eq([{"size" => ["512"]}])
        end
      end

      context "when selecting the newer empty filter" do
        let(:current_filter) { empty_b }

        it "keeps the older empty duplicate and the explicit-valued child" do
          expect(service_result.matching_filters).to eq({})
          expect(service_result.ignored_filters).to eq([{}, {"size" => ["512"]}])
        end
      end

      context "when selecting the explicit-valued filter" do
        let(:current_filter) { with_values }

        it "does not include empty filters as children" do
          expect(service_result.matching_filters).to eq({"size" => ["512"]})
          expect(service_result.ignored_filters).to eq([])
        end
      end
    end

    context "when a child's values are a strict subset of the parent's" do
      let(:current_filter) { create_filter }
      let(:child_filter) { create_filter }

      before do
        create_filter_values(current_filter, size_filter, %w[512 1024])
        create_filter_values(child_filter, size_filter, ["512"])
      end

      it "keeps the same-key subset child verbatim" do
        expect(service_result.matching_filters).to eq({"size" => %w[512 1024]})
        expect(service_result.ignored_filters).to eq([{"size" => ["512"]}])
      end

      context "with an additional different-key child" do
        before do
          different_key_child = create_filter
          create_filter_values(different_key_child, size_filter, ["512"])
          create_filter_values(different_key_child, steps_filter, ["25"])
        end

        it "keeps both the same-key subset and different-key child intact" do
          expect(service_result.matching_filters).to eq({"size" => %w[512 1024]})
          expect(service_result.ignored_filters).to eq([
            {"size" => ["512"]},
            {"size" => ["512"], "steps" => ["25"]}
          ])
        end
      end
    end

    context "when selecting all configured values" do
      let(:current_filter) { create_filter }
      let(:child_filter) { create_filter }

      before do
        create_filter_values(current_filter, size_filter, nil)
        create_filter_values(child_filter, size_filter, ["512"])
      end

      it "expands the configured metric values and ignores the explicit child" do
        expect(service_result.matching_filters).to eq({"size" => %w[512 1024]})
        expect(service_result.ignored_filters).to eq([{"size" => ["512"]}])
        expect(target_filter.all_filter_values?(current_filter, "size")).to be(true)
        expect(target_filter.all_filter_values?(child_filter, "size")).to be(false)
      end
    end

    context "when a child is a subset on one key but partially overlaps another" do
      let(:current_filter) { create_filter }

      before do
        create_filter_values(current_filter, size_filter, %w[512 1024])
        create_filter_values(current_filter, steps_filter, %w[25 50])
        mixed_child = create_filter
        create_filter_values(mixed_child, size_filter, ["512"])
        create_filter_values(mixed_child, steps_filter, %w[25 75])
      end

      it "subtracts matching values from the non-subset child" do
        expect(service_result.matching_filters).to eq({"size" => %w[512 1024], "steps" => %w[25 50]})
        expect(service_result.ignored_filters).to eq([{"size" => [], "steps" => ["75"]}])
      end
    end

    context "when filters have identical keys and values" do
      let(:filter_a) { create_filter(created_at: 3.days.ago) }
      let(:filter_b) { create_filter(created_at: 2.days.ago) }
      let(:filter_c) { create_filter(created_at: 1.day.ago) }

      before do
        [filter_a, filter_b, filter_c].each do |filter|
          create_filter_values(filter, size_filter, ["512"])
          create_filter_values(filter, steps_filter, ["25"])
        end
      end

      context "when selecting the oldest duplicate" do
        let(:current_filter) { filter_a }

        it "drops both newer siblings" do
          expect(service_result.matching_filters).to eq({"size" => ["512"], "steps" => ["25"]})
          expect(service_result.ignored_filters).to eq([])
        end
      end

      context "when selecting the middle duplicate" do
        let(:current_filter) { filter_b }

        it "keeps only the older sibling verbatim" do
          expect(service_result.matching_filters).to eq({"size" => ["512"], "steps" => ["25"]})
          expect(service_result.ignored_filters).to eq([{"size" => ["512"], "steps" => ["25"]}])
        end
      end

      context "when selecting the newest duplicate" do
        let(:current_filter) { filter_c }

        it "keeps both older siblings verbatim" do
          expect(service_result.matching_filters).to eq({"size" => ["512"], "steps" => ["25"]})
          expect(service_result.ignored_filters).to eq([
            {"size" => ["512"], "steps" => ["25"]},
            {"size" => ["512"], "steps" => ["25"]}
          ])
        end
      end
    end

    context "when an identical child enumerates keys in reverse order" do
      let(:current_filter) { create_filter(created_at: 2.days.ago) }
      let(:duplicate) { create_filter(created_at: 1.day.ago) }

      before do
        create_filter_values(current_filter, size_filter, ["512"], ordered_at: 2.days.ago)
        create_filter_values(current_filter, steps_filter, ["25"], ordered_at: 1.day.ago)
        create_filter_values(duplicate, steps_filter, ["25"], ordered_at: 2.days.ago)
        create_filter_values(duplicate, size_filter, ["512"], ordered_at: 1.day.ago)
      end

      it "recognizes and drops the newer duplicate despite different key order" do
        expect(current_filter.to_h_with_all_values.keys).to eq(%w[size steps])
        expect(duplicate.to_h_with_all_values.keys).to eq(%w[steps size])
        expect(service_result.matching_filters).to eq({"size" => ["512"], "steps" => ["25"]})
        expect(service_result.ignored_filters).to eq([])
      end
    end

    context "when identical filters share the same created_at" do
      let(:created_at) { 1.day.ago }
      let(:filter_a) { create_filter(created_at:) }
      let(:filter_b) { create_filter(created_at:) }

      before do
        create_filter_values(filter_a, size_filter, ["512"])
        create_filter_values(filter_b, size_filter, ["512"])
      end

      context "when selecting the lowest id" do
        let(:current_filter) { [filter_a, filter_b].min_by(&:id) }

        it "drops the identical sibling" do
          expect(service_result.matching_filters).to eq({"size" => ["512"]})
          expect(service_result.ignored_filters).to eq([])
        end
      end

      context "when selecting the highest id" do
        let(:current_filter) { [filter_a, filter_b].max_by(&:id) }

        it "keeps the identical sibling verbatim" do
          expect(service_result.matching_filters).to eq({"size" => ["512"]})
          expect(service_result.ignored_filters).to eq([{"size" => ["512"]}])
        end
      end
    end

    context "with an unsaved empty default bucket" do
      let(:current_filter) { filter_class.new }

      before do
        create_filter_values(create_filter, size_filter, ["512"])
        create_filter_values(create_filter, steps_filter, ["25"])
      end

      it "matches the default bucket and excludes every configured filter" do
        expect(current_filter).to be_new_record
        expect(service_result.matching_filters).to eq({})
        expect(service_result.ignored_filters).to eq([{"size" => ["512"]}, {"steps" => ["25"]}])
      end
    end
  end

  context "with a charge target" do
    let(:charge) { create(:standard_charge, billable_metric:) }
    let(:filter_class) { ChargeFilter }
    let(:filter_tables) { %w[charge_filters charge_filter_values billable_metric_filters] }

    def create_filter(**attributes)
      create(:charge_filter, charge:, **attributes)
    end

    def create_filter_values(filter, metric_filter, values, ordered_at: Time.current)
      create(:charge_filter_value, charge_filter: filter, billable_metric_filter: metric_filter,
        values: values || [ChargeFilterValue::ALL_FILTER_VALUES], updated_at: ordered_at)
    end

    def build_target(filter, reload: false, preload: false)
      source = if preload
        Charge.includes(filters: {values: :billable_metric_filter}).find(charge.id)
      elsif reload
        Charge.find(charge.id)
      else
        charge
      end
      Events::BillingPeriodFilters::FilterTarget.from_charge(charge: source, filter:)
    end

    include_examples "matching and ignored filters"
  end

  context "with a billing segment target" do
    let(:filter_class) { ProductFilter }
    let(:filter_tables) { %w[product_filters product_filter_values billable_metric_filters] }
    let(:product) { create(:product, organization:, billable_metric:) }
    let(:contract) { create(:contract, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
    let(:rate_card_rate) { create(:rate_card_rate, organization:, rate_card:) }
    let(:billing_segment) do
      create(:billing_segment, organization:, customer: contract.customer, contract:, contract_rate_card:, rate_card_rate:)
    end

    def create_filter(**attributes)
      create(:product_filter, organization:, product:, **attributes)
    end

    def create_filter_values(filter, metric_filter, values, ordered_at: Time.current)
      (values || [nil]).each do |value|
        create(:product_filter_value, organization:, product_filter: filter, billable_metric_filter: metric_filter,
          value:, created_at: ordered_at)
      end
    end

    def build_target(filter, reload: false, preload: false)
      source = if preload
        BillingSegment.includes(contract_rate_card: {product: {filters: {values: :billable_metric_filter}}})
          .find(billing_segment.id)
      elsif reload
        BillingSegment.find(billing_segment.id)
      else
        billing_segment
      end
      Events::BillingPeriodFilters::FilterTarget.from_billing_segment(billing_segment: source, filter:)
    end

    include_examples "matching and ignored filters"
  end
end
