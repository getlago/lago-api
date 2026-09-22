# frozen_string_literal: true

require "rails_helper"

RSpec.describe RealtimeUsage::RecentEventsService, clickhouse: {clean_before: true} do
  subject(:recent_events) { described_class.call(subscription:, since:) }

  let(:organization) { create(:organization, clickhouse_events_store: true) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:) }
  let(:since) { 1.minute.ago }

  context "with an organization reading the clickhouse events store" do
    it "reports the events received since the given time" do
      create(
        :clickhouse_events_enriched,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: 10.seconds.ago
      )

      expect(recent_events.received).to be(true)
    end

    it "ignores the events received before" do
      create(
        :clickhouse_events_enriched,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        code: billable_metric.code,
        timestamp: 10.minutes.ago
      )

      expect(recent_events.received).to be(false)
    end
  end

  context "with an organization reading the postgres events store" do
    let(:organization) { create(:organization) }

    it "reports the events received since the given time" do
      create(:event, organization:, external_subscription_id: subscription.external_id, timestamp: 10.seconds.ago)

      expect(recent_events.received).to be(true)
    end

    it "ignores the events received before" do
      create(:event, organization:, external_subscription_id: subscription.external_id, timestamp: 10.minutes.ago)

      expect(recent_events.received).to be(false)
    end
  end
end
