# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::TerminateAllEndedService do
  subject(:result) { described_class.call(timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:timestamp) { Time.zone.parse("2026-09-30T00:05:00Z") }
  let(:started_at) { Time.zone.parse("2026-09-01T00:00:00Z") }

  let(:ended) { create(:contract, organization:, customer:, started_at:, ended_at: Time.zone.parse("2026-09-30T00:00:00Z")) }
  let(:ending_later) { create(:contract, organization:, customer:, started_at:, ended_at: Time.zone.parse("2026-10-01T00:00:00Z")) }
  let(:of_deleted_customer) do
    create(:contract, organization:, customer: create(:customer, organization:, deleted_at: 1.day.ago), started_at:,
      ended_at: Time.zone.parse("2026-09-29T00:00:00Z"))
  end

  before do
    ended
    ending_later
    of_deleted_customer
  end

  it "enqueues a termination for each active contract whose planned end has arrived" do
    expect(result).to be_success
    expect(Contracts::TerminateJob).to have_been_enqueued.exactly(:once)
    expect(Contracts::TerminateJob).to have_been_enqueued.with(ended)
  end
end
