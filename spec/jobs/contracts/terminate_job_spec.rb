# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::TerminateJob do
  subject(:terminate_job) { described_class }

  let(:ended_at) { 1.hour.ago.change(usec: 0) }
  let(:contract) { create(:contract, started_at: 1.month.ago, ended_at:) }

  before { allow(Contracts::TerminateService).to receive(:call!) }

  it "terminates the contract at its planned end" do
    terminate_job.perform_now(contract)

    expect(Contracts::TerminateService).to have_received(:call!).with(contract:, timestamp: ended_at)
  end

  context "when the contract was terminated since it was enqueued" do
    let(:contract) { create(:contract, :terminated, started_at: 1.month.ago, ended_at:) }

    it "leaves it alone" do
      terminate_job.perform_now(contract)

      expect(Contracts::TerminateService).not_to have_received(:call!)
    end
  end

  context "when its end was moved later since it was enqueued" do
    let(:ended_at) { 1.day.from_now }

    it "leaves it alone" do
      terminate_job.perform_now(contract)

      expect(Contracts::TerminateService).not_to have_received(:call!)
    end
  end

  context "when the customer's billing lock is held" do
    before do
      allow(Contracts::TerminateService).to receive(:call!)
        .and_raise(BaseService::LockAcquisitionFailure.new(nil, code: "lock_acquisition_failed", error_message: "Failed to acquire lock"))
    end

    it "retries the job instead of dying" do
      expect { terminate_job.perform_now(contract) }.to have_enqueued_job(described_class)
    end
  end
end
