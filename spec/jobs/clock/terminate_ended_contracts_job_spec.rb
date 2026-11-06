# frozen_string_literal: true

require "rails_helper"

describe Clock::TerminateEndedContractsJob, job: true do
  subject { described_class }

  it_behaves_like "a unique job" do
    let(:job_args) { [] }
  end

  describe ".perform" do
    before { allow(Contracts::TerminateAllEndedService).to receive(:call!) }

    it "terminates the ended contracts" do
      freeze_time do
        described_class.perform_now

        expect(Contracts::TerminateAllEndedService).to have_received(:call!).with(timestamp: Time.current)
      end
    end
  end
end
