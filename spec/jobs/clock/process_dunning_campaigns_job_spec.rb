# frozen_string_literal: true

require 'rails_helper'

describe Clock::ProcessDunningCampaignsJob, job: true do
  subject { described_class }

  describe '.perform' do
    context "when premium features are enabled" do
      around { |test| lago_premium!(&test) }

      it "queue a DunningCampaigns::ProcessDunningCampaignsJob" do
        described_class.perform_now
        expect(Dunning::ProcessCampaignsJob).to have_been_enqueued
      end
    end

    it "does nothing" do
      described_class.perform_now
      expect(Dunning::ProcessCampaignsJob).not_to have_been_enqueued
    end
  end
end
