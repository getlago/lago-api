# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycles::ProcessJob do
  let(:subscription) { create(:subscription) }
  let(:billing_at) { Time.utc(2026, 7, 1) }

  before { allow(BillingCycles::ProcessService).to receive(:call!) }

  it "calls the process service for the subscription and billing_at" do
    described_class.perform_now(subscription, billing_at)

    expect(BillingCycles::ProcessService).to have_received(:call!).with(subscription:, billing_at:)
  end
end
