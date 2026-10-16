# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::PreviousSubscriptionSnapshots do
  subject(:lookup) { described_class.new(subscription) }

  let(:organization) { create(:organization) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }
  let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu us]) }
  let(:charge) { create(:standard_charge, organization:, billable_metric:) }
  let(:previous_charge) { create(:standard_charge, organization:, billable_metric:) }
  let(:previous_subscription) { create(:subscription, organization:, plan: previous_charge.plan) }
  let(:subscription) do
    create(:subscription, organization:, plan: charge.plan, customer: previous_subscription.customer, previous_subscription:)
  end
  let(:termination_datetime) { Time.zone.parse("2026-10-01T00:00:01") }

  def create_filter(target_charge, values)
    create(:charge_filter, charge: target_charge).tap do |filter|
      create(:charge_filter_value, charge_filter: filter, billable_metric_filter:, values:)
    end
  end

  def create_previous_snapshot(**attributes)
    create(
      :recurring_aggregation_snapshot,
      organization:, subscription: previous_subscription, charge: previous_charge, **attributes
    )
  end

  def count_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
    count
  end

  describe "#records" do
    let(:eu_filter) { create_filter(charge, %w[eu]) }
    let(:us_filter) { create_filter(charge, %w[us]) }
    let(:previous_eu_filter) { create_filter(previous_charge, %w[eu]) }
    let(:previous_us_filter) { create_filter(previous_charge, %w[us]) }

    before do
      eu_filter
      us_filter
      create_previous_snapshot(to_datetime: termination_datetime, units: 7)
      create_previous_snapshot(to_datetime: termination_datetime - 1.month, charge_filter: previous_eu_filter, units: 1)
      create_previous_snapshot(to_datetime: termination_datetime, charge_filter: previous_eu_filter, units: 3)
      # A filter without snapshot in the last period still returns its latest one
      create_previous_snapshot(to_datetime: termination_datetime - 1.month, charge_filter: previous_us_filter, units: 5)
      subscription
    end

    it "returns the latest snapshots of the bucket with the same filter" do
      expect(lookup.records(charge:, charge_filter: eu_filter).map(&:units)).to eq([3])
      expect(lookup.records(charge:, charge_filter: us_filter).map(&:units)).to eq([5])
      expect(lookup.records(charge:, charge_filter: build(:charge_filter, charge:)).map(&:units)).to eq([7])
    end

    it "loads the previous charges and their snapshots once for all buckets" do
      fresh_charge = Charge.includes(filters: {values: :billable_metric_filter}).find(charge.id)
      buckets = fresh_charge.filters.to_a + [build(:charge_filter, charge: fresh_charge)]

      first_bucket_queries = count_queries { lookup.records(charge: fresh_charge, charge_filter: buckets.first) }
      other_buckets_queries = count_queries do
        buckets.drop(1).each { lookup.records(charge: fresh_charge, charge_filter: it) }
      end

      expect(first_bucket_queries).to eq(5)
      expect(other_buckets_queries).to eq(0)
    end

    context "without previous subscription" do
      let(:subscription) { create(:subscription, organization:, plan: charge.plan) }

      it "returns no snapshot without querying" do
        expect(count_queries { expect(lookup.records(charge:, charge_filter: eu_filter)).to eq([]) }).to eq(0)
      end
    end

    context "when the previous charge has other filters" do
      before { create_filter(previous_charge, %w[eu us]) }

      it "returns no snapshot" do
        expect(lookup.records(charge:, charge_filter: eu_filter)).to eq([])
      end
    end
  end
end
