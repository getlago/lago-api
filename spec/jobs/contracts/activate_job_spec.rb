# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::ActivateJob do
  subject(:activate_job) { described_class }

  let(:contract) { create(:contract, :pending) }

  before { allow(Contracts::ActivateService).to receive(:call!) }

  it "activates the contract" do
    activate_job.perform_now(contract)

    expect(Contracts::ActivateService).to have_received(:call!).with(contract:)
  end

  context "when the billing schedule is locked" do
    before do
      allow(Contracts::ActivateService).to receive(:call!).and_call_original
      allow(Customers::LockService).to receive(:call).and_raise(BaseLockService::FailedToAcquireLock)
    end

    it "retries activation without starting the contract" do
      expect { activate_job.perform_now(contract) }.to have_enqueued_job(described_class).with(contract)
      expect(contract.reload).to be_pending
    end
  end
end
