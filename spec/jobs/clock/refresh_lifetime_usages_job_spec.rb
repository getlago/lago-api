# frozen_string_literal: true

require 'rails_helper'

describe Clock::RefreshLifetimeUsagesJob, job: true do
  subject { described_class }

  describe '.perform' do
    let(:lifetime_usage1) { create(:lifetime_usage, recalculate_invoiced_usage: true) }
    let(:lifetime_usage2) { create(:lifetime_usage, recalculate_current_usage: true) }
    let(:lifetime_usage3) { create(:lifetime_usage, recalculate_invoiced_usage: false, recalculate_current_usage: false) }

    before do
      lifetime_usage1
      lifetime_usage2
      lifetime_usage3
    end

    context 'when freemium' do
      it 'does not call the refresh service' do
        described_class.perform_now
        expect(LifetimeUsages::RecalculateAndCheckJob).not_to have_been_enqueued.with(lifetime_usage1)
        expect(LifetimeUsages::RecalculateAndCheckJob).not_to have_been_enqueued.with(lifetime_usage2)
        expect(LifetimeUsages::RecalculateAndCheckJob).not_to have_been_enqueued.with(lifetime_usage3)
      end
    end

    context 'when premium' do
      around { |test| lago_premium!(&test) }

      it "enqueues a job for every usage that needs to be recalculated" do
        described_class.perform_now

        expect(LifetimeUsages::RecalculateAndCheckJob).to have_been_enqueued.with(lifetime_usage1)
        expect(LifetimeUsages::RecalculateAndCheckJob).to have_been_enqueued.with(lifetime_usage2)
        expect(LifetimeUsages::RecalculateAndCheckJob).not_to have_been_enqueued.with(lifetime_usage3)
      end
    end
  end
end
