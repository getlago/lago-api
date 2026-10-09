# frozen_string_literal: true

require "rails_helper"

describe Clock::ActivateContractsJob, job: true do
  subject { described_class }

  it_behaves_like "a unique job" do
    let(:job_args) { [] }
  end

  describe ".perform" do
    before { allow(Contracts::ActivateAllPendingService).to receive(:call!) }

    it "activates the pending contracts" do
      freeze_time do
        described_class.perform_now

        expect(Contracts::ActivateAllPendingService).to have_received(:call!).with(timestamp: Time.current)
      end
    end
  end
end
