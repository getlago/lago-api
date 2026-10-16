# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::ActivateAllPendingService do
  subject(:result) { described_class.call(timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tokyo_customer) { create(:customer, organization:, timezone: "Asia/Tokyo") }
  let(:timestamp) { Time.zone.parse("2026-09-30T00:05:00Z") }

  let(:started) { create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2026-09-30T00:00:00Z")) }
  let(:scheduled) { create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2026-10-01T00:00:00Z")) }
  # Tokyo's Sept 30 began at 15:00 UTC the day before.
  let(:started_in_tokyo) do
    create(:contract, :pending, organization:, customer: tokyo_customer, started_at: Time.zone.parse("2026-09-29T15:00:00Z"))
  end
  let(:of_deleted_customer) do
    create(:contract, :pending, organization:, customer: create(:customer, organization:, deleted_at: 1.day.ago), started_at: Time.zone.parse("2026-09-29T00:00:00Z"))
  end

  before do
    started
    scheduled
    started_in_tokyo
    of_deleted_customer
  end

  it "enqueues an activation for each pending contract whose start has arrived" do
    expect(result).to be_success
    expect(Contracts::ActivateJob).to have_been_enqueued.exactly(2).times
    expect(Contracts::ActivateJob).to have_been_enqueued.with(started)
    expect(Contracts::ActivateJob).to have_been_enqueued.with(started_in_tokyo)
  end
end
