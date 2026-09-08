# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::CreateBillingSegmentsJob do
  it "enqueues one job per due customer, even across multiple cards and contracts" do
    customer = create(:customer)
    2.times do
      contract = create(:contract, customer:)
      create(:contract_rate_card, organization: customer.organization, contract:, next_billing_at: 1.hour.ago)
    end
    create(:contract_rate_card, next_billing_at: 1.hour.from_now)
    create(:contract_rate_card, contract: create(:contract, :pending), next_billing_at: 1.hour.ago)

    described_class.perform_now

    expect(BillingSegments::ScheduleJob).to have_been_enqueued.once.with(customer.id)
    expect(described_class).not_to have_been_enqueued
  end

  it "continues after the last customer of a full batch" do
    stub_const("Clock::CreateBillingSegmentsJob::BATCH_SIZE", 1)
    customers = Array.new(2) do
      card = create(:contract_rate_card, next_billing_at: 1.hour.ago)
      card.contract.customer
    end.sort_by(&:id)

    described_class.perform_now
    described_class.perform_now(customers.first.id)
    described_class.perform_now(customers.last.id)

    customers.each do |customer|
      expect(BillingSegments::ScheduleJob).to have_been_enqueued.once.with(customer.id)
      expect(described_class).to have_been_enqueued.once.with(customer.id)
    end
    expect(described_class).to have_been_enqueued.exactly(2).times
  end

  it "does not enqueue jobs when no cards are due" do
    described_class.perform_now

    expect(BillingSegments::ScheduleJob).not_to have_been_enqueued
    expect(described_class).not_to have_been_enqueued
  end
end
