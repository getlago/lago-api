# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::BillingPeriodFilters::ChargesResolver do
  subject(:filter_targets) { resolver.filter_targets }

  let(:resolver) { described_class.new(subscription:, boundaries:) }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) do
    create(:subscription, organization:, customer:, plan:, external_id: "subscription-id")
  end
  let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:billable_metric_filter) do
    create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us])
  end
  let(:charge_filter) { create(:charge_filter, charge:) }
  let(:boundaries) do
    BillingPeriodBoundaries.new(
      from_datetime: Time.zone.parse("2026-09-01"),
      to_datetime: Time.zone.parse("2026-09-30 23:59:59"),
      charges_from_datetime: Time.zone.parse("2026-09-01"),
      charges_to_datetime: Time.zone.parse("2026-09-30 23:59:59"),
      charges_duration: 30.days,
      timestamp: Time.zone.parse("2026-09-30 23:59:59").to_i
    )
  end

  describe "#filter_targets" do
    it "memoizes filter targets by charge instance rather than charge id" do
      create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["eu"])
      create(
        :event,
        organization:,
        customer:,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: boundaries.charges_from_datetime + 1.day,
        properties: {"region" => "eu"}
      )

      target_charges = []
      allow(Events::BillingPeriodFilters::FilterTarget).to receive(:from_charge).and_wrap_original do |method, charge:, filter: nil|
        target_charges << charge
        method.call(charge:, filter:)
      end

      filter_targets

      expect(target_charges.map(&:id)).to eq([charge.id, charge.id])
      expect(target_charges.map(&:object_id).uniq.size).to eq(2)
    end

    context "with filters on a recurring charge" do
      let(:charge_filters) { create_list(:charge_filter, 3, charge:) }
      let(:filter_value_queries) { [] }
      let(:record_query) do
        ->(*, payload) { filter_value_queries << payload[:sql] if payload[:sql].include?(%("charge_filter_values")) }
      end

      before do
        charge_filters.each do |filter|
          create(:charge_filter_value, charge_filter: filter, billable_metric_filter:, values: ["eu"])
        end
      end

      it "loads the filter values in a single query" do
        ActiveSupport::Notifications.subscribed(record_query, "sql.active_record") { filter_targets }

        expect(filter_targets[charge.target_key].keys).to match_array([*charge_filters.map(&:id), nil])
        expect(filter_value_queries.size).to eq(1)
      end
    end

    context "with a combinations cache TTL", cache: :memory do
      let(:resolver) { described_class.new(subscription:, boundaries:, combinations_cache_ttl:) }
      let(:other_resolver) { described_class.new(subscription:, boundaries:, combinations_cache_ttl:) }
      let(:combinations_cache_ttl) { 5.seconds }
      let(:billable_metric) { create(:sum_billable_metric, organization:) }
      let(:combination_queries) { [] }

      before do
        create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["eu"])
        create(
          :event,
          organization:,
          customer:,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp: boundaries.charges_from_datetime + 1.day,
          properties: {"region" => "eu"}
        )

        allow(Events::Stores::PostgresStore).to receive(:new).and_wrap_original do |build, **args|
          build.call(**args).tap do |store|
            allow(store).to receive(:distinct_codes_and_property_combinations).and_wrap_original do |query, **options|
              combination_queries << options
              query.call(**options)
            end
          end
        end
      end

      it "reuses the events store answer across resolvers" do
        expect(filter_targets).to match({charge.target_key => {charge_filter.id => be_present}})
        expect(other_resolver.filter_targets).to eq(filter_targets)
        expect(combination_queries.size).to eq(1)
      end

      it "queries the events store again once the entry expired" do
        filter_targets

        travel(6.seconds) { other_resolver.filter_targets }

        expect(combination_queries.size).to eq(2)
      end

      context "with another window" do
        let(:other_resolver) do
          described_class.new(subscription:, boundaries: other_boundaries, combinations_cache_ttl:)
        end
        let(:other_boundaries) do
          BillingPeriodBoundaries.new(
            from_datetime: Time.zone.parse("2026-08-01"),
            to_datetime: Time.zone.parse("2026-09-30 23:59:59"),
            charges_from_datetime: Time.zone.parse("2026-08-01"),
            charges_to_datetime: Time.zone.parse("2026-09-30 23:59:59"),
            charges_duration: 61.days,
            timestamp: Time.zone.parse("2026-09-30 23:59:59").to_i
          )
        end

        it "does not share the entry" do
          filter_targets
          other_resolver.filter_targets

          expect(combination_queries.size).to eq(2)
        end
      end

      context "with codes that would read the same once joined with commas" do
        let(:resolver) do
          described_class.new(subscription:, boundaries:, codes: [comma_metric.code], combinations_cache_ttl:)
        end
        let(:other_resolver) do
          described_class.new(subscription:, boundaries:, codes: [billable_metric.code, "other"], combinations_cache_ttl:)
        end
        # Same filter key as billable_metric, so only the codes tell the two queries apart.
        let(:comma_metric) { create(:sum_billable_metric, organization:, code: "#{billable_metric.code},other") }

        before do
          create(:billable_metric_filter, billable_metric: comma_metric, key: "region", values: %w[eu us])
          create(:standard_charge, plan:, billable_metric: comma_metric)
        end

        it "does not share the entry" do
          expect(filter_targets).to eq({})
          expect(other_resolver.filter_targets).to match({charge.target_key => {charge_filter.id => be_present}})
          expect(combination_queries.size).to eq(2)
        end
      end

      context "without a TTL" do
        let(:combinations_cache_ttl) { nil }

        it "queries the events store for every resolver" do
          filter_targets
          other_resolver.filter_targets

          expect(combination_queries.size).to eq(2)
        end
      end
    end

    context "with a charge served from the usage buckets" do
      let(:resolver) { described_class.new(subscription:, boundaries:, precomputed_filters:) }
      let(:precomputed_filters) { {charge => [nil, charge_filter.id]} }
      let(:billable_metric) { create(:sum_billable_metric, organization:) }
      let(:combination_queries) { [] }
      let(:queried_codes) { combination_queries.flat_map { it[:codes] } }

      before do
        create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["eu"])

        allow(Events::Stores::PostgresStore).to receive(:new).and_wrap_original do |build, **args|
          build.call(**args).tap do |store|
            allow(store).to receive(:distinct_codes_and_property_combinations).and_wrap_original do |query, **options|
              combination_queries << options
              query.call(**options)
            end
          end
        end
      end

      it "records the filters the buckets hold usage for, without querying the events store" do
        expect(filter_targets).to eq({charge.target_key => {nil => nil, charge_filter.id => nil}})
        expect(combination_queries).to be_empty
      end

      context "with a delegated charge on the same code" do
        let(:delegated_charge) { create(:standard_charge, plan:, billable_metric:) }

        before do
          delegated_charge

          create(
            :event,
            organization:,
            customer:,
            external_subscription_id: subscription.external_id,
            code: billable_metric.code,
            timestamp: boundaries.charges_from_datetime + 1.day,
            properties: {"region" => "eu"}
          )
        end

        it "keeps the code in the query and leaves the served charge to the buckets" do
          expect(filter_targets).to match(
            {
              charge.target_key => {nil => nil, charge_filter.id => nil},
              delegated_charge.target_key => {nil => be_present}
            }
          )
          expect(queried_codes).to eq([billable_metric.code])
        end
      end
    end
  end
end
