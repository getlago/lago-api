# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::ComputeAllForecastedUsageAmountsJob, type: :job do
  subject(:compute_job) { described_class }

  describe ".perform" do
    before { allow(Charges::ComputeAllForecastedUsageAmountsService).to receive(:call) }

    it "calls Charges::ComputeAllForecastedUsageAmountsService" do
      compute_job.perform_now
      expect(Charges::ComputeAllForecastedUsageAmountsService).to have_received(:call)
    end
  end
end
