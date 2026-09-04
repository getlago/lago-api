# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillableMetrics::AggregationFactory do
  subject(:factory) { described_class }

  let(:billable_metric) { create(billable_aggregation, recurring:) }
  let(:billable_aggregation) { :billable_metric }
  let(:recurring) { false }

  let(:charge) { build(:standard_charge, billable_metric:, pay_in_advance:, prorated:) }
  let(:pay_in_advance) { false }
  let(:prorated) { false }

  let(:subscription) { create(:subscription, started_at: DateTime.parse("2023-03-15")) }
  let(:boundaries) do
    {
      charges_from_datetime: subscription.started_at.beginning_of_day,
      charges_to_datetime: subscription.started_at.end_of_month.end_of_day
    }
  end

  let(:current_usage) { false }

  let(:result) { factory.new_instance(charge:, current_usage:, subscription:, boundaries:) }

  describe "#new_instance" do
    context "with count_agg aggregation" do
      let(:billable_aggregation) { :billable_metric }

      it { expect(result).to be_a(BillableMetrics::Aggregations::CountService) }
    end

    context "with latest_agg aggregation" do
      let(:billable_aggregation) { :latest_billable_metric }

      it { expect(result).to be_a(BillableMetrics::Aggregations::LatestService) }

      context "when pay_in_advance" do
        let(:pay_in_advance) { true }

        it { expect { result }.to raise_error(NotImplementedError) }

        context "when current usage" do
          let(:current_usage) { true }

          it { expect(result).to be_a(BillableMetrics::Aggregations::LatestService) }
        end
      end
    end

    context "with max_agg aggregation" do
      let(:billable_aggregation) { :max_billable_metric }

      it { expect(result).to be_a(BillableMetrics::Aggregations::MaxService) }

      context "when pay_in_advance" do
        let(:pay_in_advance) { true }

        it { expect { result }.to raise_error(NotImplementedError) }

        context "when current usage" do
          let(:current_usage) { true }

          it { expect(result).to be_a(BillableMetrics::Aggregations::MaxService) }
        end
      end
    end

    context "with sum_agg aggregation" do
      let(:billable_aggregation) { :sum_billable_metric }

      it { expect(result).to be_a(BillableMetrics::Aggregations::SumService) }

      context "when prorated" do
        let(:prorated) { true }
        let(:recurring) { true }

        it { expect(result).to be_a(BillableMetrics::ProratedAggregations::SumService) }
      end
    end

    context "with unique_count_agg aggregation" do
      let(:billable_aggregation) { :unique_count_billable_metric }

      it { expect(result).to be_a(BillableMetrics::Aggregations::UniqueCountService) }

      context "when prorated" do
        let(:prorated) { true }
        let(:recurring) { true }

        it { expect(result).to be_a(BillableMetrics::ProratedAggregations::UniqueCountService) }
      end
    end

    context "with weighted_sum_agg aggregation" do
      let(:billable_aggregation) { :weighted_sum_billable_metric }

      it { expect(result).to be_a(BillableMetrics::Aggregations::WeightedSumService) }

      context "when pay_in_advance" do
        let(:pay_in_advance) { true }

        it { expect { result }.to raise_error(NotImplementedError) }

        context "when current usage" do
          let(:current_usage) { true }

          it { expect(result).to be_a(BillableMetrics::Aggregations::WeightedSumService) }
        end
      end
    end

    context "with custom_agg aggregation" do
      let(:billable_aggregation) { :custom_billable_metric }

      it { expect(result).to be_a(BillableMetrics::Aggregations::CustomService) }
    end

    describe "the event store the aggregator is built with" do
      let(:store) { result.__send__(:event_store) }

      it "carries the metric, the subscription and the aggregation window" do
        expect(store).to be_a(Events::Stores::PostgresStore)
        expect(store.code).to eq(billable_metric.code)
        expect(store.subscription).to eq(subscription)
        expect(store.boundaries).to eq(boundaries)
        expect(store.deduplicate).to be(false)
      end

      it "forwards the aggregation filters" do
        charge_filter = create(:charge_filter, charge: create(:standard_charge, billable_metric:))
        filters = {charge_id: charge.id, charge_filter:}

        store = factory.new_instance(charge:, subscription:, boundaries:, filters:).__send__(:event_store)

        expect(store.filters).to eq(filters)
      end

      context "when the organization deduplicates its clickhouse events" do
        include_context "with clickhouse availability"

        let(:billable_metric) do
          create(
            billable_aggregation,
            recurring:,
            organization: create(:organization, clickhouse_events_store: true, clickhouse_deduplication_enabled: true)
          )
        end

        it "resolves the store class and the deduplication mode from the organization" do
          expect(store).to be_a(Events::Stores::ClickhouseStore)
          expect(store.deduplicate).to be(true)
        end
      end

      context "with a provider running on the same subscription and window" do
        let(:provider) do
          Events::Stores::Provider.new(organization: billable_metric.organization, subscription:, boundaries:)
        end

        it "mints the store from it rather than building another one" do
          allow(Events::Stores::Provider).to receive(:new).and_call_original
          provider # built here, before the factory runs
          allow(provider).to receive(:store_for).and_call_original

          store = factory.new_instance(charge:, subscription:, boundaries:, provider:).__send__(:event_store)

          expect(provider).to have_received(:store_for)
          expect(Events::Stores::Provider).to have_received(:new).once
          expect(store.code).to eq(billable_metric.code)
        end
      end

      context "with a provider running on another window" do
        let(:provider) do
          Events::Stores::Provider.new(
            organization: billable_metric.organization,
            subscription:,
            boundaries: boundaries.merge(max_timestamp: subscription.started_at)
          )
        end

        it "refuses to mint a store for a scope it does not aggregate" do
          expect { factory.new_instance(charge:, subscription:, boundaries:, provider:) }
            .to raise_error(ArgumentError, /another subscription or window/)
        end
      end

      context "with a provider running on another subscription" do
        let(:provider) do
          Events::Stores::Provider.new(
            organization: billable_metric.organization,
            subscription: create(:subscription),
            boundaries:
          )
        end

        it "refuses to mint a store for a scope it does not aggregate" do
          expect { factory.new_instance(charge:, subscription:, boundaries:, provider:) }
            .to raise_error(ArgumentError, /another subscription or window/)
        end
      end
    end
  end
end
