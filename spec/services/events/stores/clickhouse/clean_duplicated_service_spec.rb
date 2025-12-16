# frozen_string_literal: true

require "spec_helper"

RSpec.describe Events::Stores::Clickhouse::CleanDuplicatedService, :clickhouse do
  subject(:clean_service) { described_class.new(subscription:, timestamp:) }

  let(:organization) { create(:organization, clickhouse_events_store: true) }
  let(:subscription) { create(:subscription, organization:) }
  let(:timestamp) { Time.current }

  describe "#call" do
    let(:transaction_id) { SecureRandom.uuid }
    let(:timestamp) { Time.current.change(usec: 0) }

    let(:base_enriched_at) { Time.current - 10.minutes }

    before do
      3.times do |i|
        create(
          :clickhouse_events_enriched,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          transaction_id: transaction_id,
          timestamp: timestamp,
          code: "event_code_#{SecureRandom.hex(4)}",
          enriched_at: base_enriched_at + i.minutes
        )
      end

      allow(Subscriptions::ChargeCacheService).to receive(:expire_for_subscription)
    end

    it "removes duplicated events" do
      expect(::Clickhouse::EventsEnriched.where(transaction_id:, timestamp:).count).to eq(3)

      result = clean_service.call

      expect(result).to be_success
      expect(::Clickhouse::EventsEnriched.where(transaction_id:, timestamp:).count).to eq(1)

      event = ::Clickhouse::EventsEnriched.find_by(transaction_id:, timestamp:)
      expect(event.enriched_at).to match_datetime(base_enriched_at + 2.minutes)

      expect(Subscriptions::ChargeCacheService).to have_received(:expire_for_subscription).with(subscription)
    end
  end
end
