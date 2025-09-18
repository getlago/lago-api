# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyUsages::ComputeJob do
  subject(:compute_job) { described_class }

  let(:subscription) { create(:subscription) }
  let(:timestamp) { Time.current }

  let(:result) { BaseService::Result.new }

  describe ".perform" do
    it "delegates to DailyUsages::ComputeService" do
      allow(DailyUsages::ComputeService).to receive(:call)
        .with(subscription:, timestamp:)
        .and_return(result)

      compute_job.perform_now(subscription, timestamp:)

      expect(DailyUsages::ComputeService).to have_received(:call)
        .with(subscription:, timestamp:).once
    end
  end
end
