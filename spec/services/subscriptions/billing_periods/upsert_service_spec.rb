# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::BillingPeriods::UpsertService do
  subject(:service_result) { described_class.call(subscription:, timestamp:) }

  let(:subscription) do
    create(
      :subscription,
      subscription_at: Time.zone.parse("2026-01-15T10:00:00"),
      started_at: Time.zone.parse("2026-01-15T10:00:00"),
      billing_time: :calendar
    )
  end
  let(:timestamp) { Time.zone.parse("2026-08-07T12:00:00") }

  it "upserts the covering period and the next one" do
    expect { service_result }.to change(SubscriptionBillingPeriod, :count).by(2)

    current, upcoming = subscription.reload
      .then { SubscriptionBillingPeriod.where(subscription_id: subscription.id).order(:charges_from).to_a }

    expect(current.charges_from).to be <= timestamp
    expect(current.charges_to).to be >= timestamp
    expect(current.organization_id).to eq(subscription.organization_id)

    expect(upcoming.charges_from).to be > current.charges_to
    expect(upcoming.charges_from).to be <= current.charges_to + 1.day
  end

  it "is idempotent" do
    described_class.call(subscription:, timestamp:)

    expect { service_result }.not_to change(SubscriptionBillingPeriod, :count)
  end
end
