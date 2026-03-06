# frozen_string_literal: true

require "spec_helper"

RSpec.describe Events::Stores::Clickhouse::CleanDuplicatedEnrichedExpandedService, :clickhouse do
  subject(:service) { described_class.new(subscription:, codes:) }

  let(:organization) { create(:organization, clickhouse_events_store: true) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, plan:, started_at: 1.month.ago) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, billable_metric:, plan:) }
  let(:charge_filter) { nil }
  let(:codes) { [] }

  let(:transaction_id) { SecureRandom.uuid }
  let(:event_timestamp) { Time.current.change(usec: 0) }
  let(:base_enriched_at) { Time.current.change(usec: 0) - 10.minutes }

  describe "#call" do
    before do
      3.times do |i|
        create(
          :clickhouse_events_enriched_expanded,
          organization_id: organization.id,
          subscription_id: subscription.id,
          external_subscription_id: subscription.external_id,
          charge_id: charge.id,
          charge_filter_id: charge_filter&.id || "",
          transaction_id: transaction_id,
          timestamp: event_timestamp,
          code: billable_metric.code,
          enriched_at: base_enriched_at + i.minutes
        )
      end
    end

    it "removes duplicated events and keeps the latest enriched_at" do
      result = service.call

      expect(result).to be_success

      remaining = ::Clickhouse::EventsEnrichedExpanded.where(
        organization_id: organization.id,
        subscription_id: subscription.id,
        transaction_id: transaction_id,
        timestamp: event_timestamp
      )
      expect(remaining.count).to eq(1)
      expect(remaining.first.enriched_at).to match_datetime(base_enriched_at + 2.minutes)
    end

    context "with codes filter" do
      let(:codes) { [billable_metric.code] }
      let(:other_metric) { create(:billable_metric, organization:) }
      let(:other_charge) { create(:standard_charge, billable_metric: other_metric, plan:) }

      before do
        create(
          :clickhouse_events_enriched_expanded,
          organization_id: organization.id,
          subscription_id: subscription.id,
          external_subscription_id: subscription.external_id,
          charge_id: other_charge.id,
          charge_filter_id: "",
          transaction_id: transaction_id,
          timestamp: event_timestamp,
          code: other_metric.code,
          enriched_at: base_enriched_at - 1.minute
        )
      end

      it "only removes duplicates matching the specified codes" do
        result = service.call

        expect(result).to be_success
        expect(::Clickhouse::EventsEnrichedExpanded.where(code: other_metric.code).count).to eq(1)
      end
    end

    context "with charge filter" do
      let(:charge_filter) { create(:charge_filter, charge:) }

      it "only removes duplicates matching the specified charge filter" do
        result = service.call

        expect(result).to be_success

        remaining = ::Clickhouse::EventsEnrichedExpanded.where(
          organization_id: organization.id,
          subscription_id: subscription.id,
          transaction_id: transaction_id,
          timestamp: event_timestamp
        )
        expect(remaining.count).to eq(1)
        expect(remaining.first.enriched_at).to match_datetime(base_enriched_at + 2.minutes)
      end
    end
  end
end
