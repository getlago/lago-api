# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::Stores::Provider do
  subject(:provider) { described_class.new(organization:, subscription:, boundaries:) }

  let(:organization) { create(:organization) }
  let(:subscription) { create(:subscription, organization:) }
  let(:boundaries) { {from_datetime: Time.current.beginning_of_month, to_datetime: Time.current} }

  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }

  describe "#store_for" do
    it "returns a store configured for the charge and the computation window" do
      store = provider.store_for(charge:)

      expect(store).to be_a(Events::Stores::PostgresStore)
      expect(store.code).to eq(billable_metric.code)
      expect(store.subscription).to eq(subscription)
      expect(store.boundaries).to eq(boundaries)
      expect(store.deduplicate).to be(false)
    end

    it "forwards the filters" do
      charge_filter = create(:charge_filter, charge:)
      filters = {charge_id: charge.id, charge_filter:, matching_filters: {"key" => ["value"]}, ignored_filters: []}

      store = provider.store_for(charge:, filters:)

      expect(store.filters).to eq(filters)
      expect(store.matching_filters).to eq({"key" => ["value"]})
    end

    it "mints one instance per call, so aggregators cannot share per-charge state" do
      first = provider.store_for(charge:)
      second = provider.store_for(charge:)

      expect(first).not_to be(second)

      first.aggregation_property = "total_count"
      expect(second.aggregation_property).to be_nil
    end
  end

  describe "#plain_store" do
    it "returns a store with no metric code" do
      store = provider.plain_store

      expect(store).to be_a(Events::Stores::PostgresStore)
      expect(store.code).to be_nil
      expect(store.boundaries).to eq(boundaries)
    end
  end

  describe "#store_class" do
    it "resolves the postgres store by default" do
      expect(provider.store_class).to eq(Events::Stores::PostgresStore)
    end

    context "with a clickhouse organization" do
      include_context "with clickhouse availability"

      let(:organization) { create(:organization, clickhouse_events_store: true) }

      it "resolves the clickhouse store" do
        expect(provider.store_class).to eq(Events::Stores::ClickhouseStore)
      end
    end

    context "with an active store override" do
      it "honors the override" do
        Events::Stores::StoreFactory.with_override(store_class: Events::Stores::ClickhouseStore, deduplicate: true) do
          expect(provider.store_class).to eq(Events::Stores::ClickhouseStore)
        end
      end
    end
  end

  describe "#deduplicate" do
    it "is false when the organization does not deduplicate" do
      expect(provider.deduplicate).to be(false)
    end

    context "when the organization deduplicates its clickhouse events" do
      let(:organization) do
        create(:organization, clickhouse_events_store: true, clickhouse_deduplication_enabled: true)
      end

      it "is true" do
        expect(provider.deduplicate).to be(true)
      end
    end

    context "with an active store override" do
      it "honors the override" do
        Events::Stores::StoreFactory.with_override(store_class: Events::Stores::PostgresStore, deduplicate: true) do
          expect(provider.deduplicate).to be(true)
        end
      end
    end
  end
end
