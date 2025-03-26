# frozen_string_literal: true

require "rails_helper"

describe Clock::ProcessDunningCampaignsJob, job: true do
  before do
    create(:organization, premium_integrations: [])
    create_list(:organization, 2, premium_integrations: %w[auto_dunning])
  end

  describe ".perform" do
    context "when premium features are enabled" do
      around { |test| lago_premium!(&test) }

      it "queue a DunningCampaigns::ProcessDunningCampaignsJob" do
        described_class.perform_now
        expect(DunningCampaigns::OrganizationProcessJob).to have_been_enqueued.exactly(2).times
      end
    end

    it "does nothing" do
      described_class.perform_now
      expect(DunningCampaigns::OrganizationProcessJob).not_to have_been_enqueued
    end
  end
end
