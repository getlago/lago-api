# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::SubscriptionKey do
  subject(:key) { described_class.new(subscription:, charge:) }

  let(:organization) { create(:organization) }
  let(:charge) { create(:standard_charge, organization:) }
  let(:subscription) { create(:subscription, organization:, plan: charge.plan) }
  let(:charge_filter) { create(:charge_filter, charge:) }

  describe "#snapshots" do
    let(:snapshot) { create_snapshot }
    let(:filter_snapshot) { create_snapshot(charge_filter:) }

    def create_snapshot(**attributes)
      create(:recurring_aggregation_snapshot, organization:, subscription:, charge:, **attributes)
    end

    before do
      snapshot
      filter_snapshot
      create_snapshot(charge: create(:standard_charge, organization:, plan: charge.plan))
      create_snapshot(subscription: create(:subscription, organization:, plan: charge.plan))
    end

    it "returns the snapshots of every bucket of the subscription's charge" do
      expect(key.snapshots).to match_array([snapshot, filter_snapshot])
    end
  end

  describe "#bucket_ids" do
    before { charge_filter }

    it "returns the default bucket and the filters asked for, every filter of the charge when nil" do
      expect(key.bucket_ids(nil)).to eq([nil, charge_filter.id])
      expect(key.bucket_ids([])).to eq([nil])
    end
  end

  describe "#marker_bucket_id" do
    it "returns the default bucket" do
      expect(key.marker_bucket_id).to be_nil
    end
  end

  describe "#bucket_id" do
    it "returns the filter's bucket, the default one without filter" do
      expect(key.bucket_id(charge_filter)).to eq(charge_filter.id)
      expect(key.bucket_id(nil)).to be_nil
    end
  end

  describe "#row_attributes" do
    it "returns the key columns but the bucket" do
      expect(key.row_attributes).to eq(
        organization_id: organization.id, subscription_id: subscription.id, charge_id: charge.id, billable_metric_id: charge.billable_metric_id
      )
    end
  end

  describe "#lock_key" do
    it "keeps the lock key of the subscription's charge and period" do
      expect(key.lock_key(Time.zone.parse("2026-09-30T23:59:59.999999")))
        .to eq("recurring-aggregation-snapshot-#{subscription.id}-#{charge.id}-2026-09-30T23:59:59.999999Z")
    end
  end
end
