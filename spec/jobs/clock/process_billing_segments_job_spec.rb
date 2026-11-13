# frozen_string_literal: true

require "rails_helper"

describe Clock::ProcessBillingSegmentsJob, job: true do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  before do
    contract = create(:contract, organization:, customer:, started_at: 1.month.ago)
    card = create(:contract_rate_card, organization:, contract:)
    create(
      :billing_operation,
      organization:,
      customer:,
      contract_rate_card: card,
      billing_at: Time.current - 1.minute,
      target_cycle_started_at: Time.current.beginning_of_month - 1.month
    )
  end

  it "keeps the queued job signature and schedules processing for the customer" do
    described_class.perform_now

    expect(BillingOperations::ProcessJob).to have_been_enqueued.with(customer.id)
  end
end
