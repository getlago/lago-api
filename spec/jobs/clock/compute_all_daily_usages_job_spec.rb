# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Clock::ComputeAllDailyUsagesJob, type: :job do
  subject(:compute_job) { described_class }

  describe '.perform' do
    before { allow(DailyUsages::ComputeAllService).to receive(:call) }

    it 'removes all old webhooks' do
      compute_job.perform_now

      expect(DailyUsages::ComputeAllService).to have_received(:call)
    end
  end
end
