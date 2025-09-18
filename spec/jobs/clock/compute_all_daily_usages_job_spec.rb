# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::ComputeAllDailyUsagesJob do
  subject(:compute_job) { described_class }

  describe ".perform" do
    before { allow(DailyUsages::ComputeAllService).to receive(:call) }

    it "calls DailyUsages::ComputeAllService" do
      freeze_time do
        compute_job.perform_now
        expect(DailyUsages::ComputeAllService).to have_received(:call).with(timestamp: Time.current)
      end
    end
  end
end
