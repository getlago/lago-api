# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ApplyRateChangeJob do
  subject(:perform_job) { described_class.perform_now(customer_id, rate_card_rate_id) }

  let(:customer) { create(:customer) }
  let(:customer_id) { customer.id }
  let(:rate_card_rate_id) { SecureRandom.uuid }

  before { allow(BillingOperations::ApplyRateChangeService).to receive(:call!) }

  it "applies the rate change for the customer" do
    perform_job
    expect(BillingOperations::ApplyRateChangeService).to have_received(:call!).with(customer:, rate_card_rate_id:)
  end

  context "when the customer no longer exists" do
    let(:customer_id) { SecureRandom.uuid }

    it "does nothing" do
      perform_job
      expect(BillingOperations::ApplyRateChangeService).not_to have_received(:call!)
    end
  end

  context "when the customer lock is busy" do
    before do
      allow(BillingOperations::ApplyRateChangeService).to receive(:call!).and_raise(BaseLockService::FailedToAcquireLock)
    end

    it "retries the customer job" do
      expect { perform_job }.to have_enqueued_job(described_class).with(customer_id, rate_card_rate_id)
    end
  end
end
