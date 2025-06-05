# frozen_string_literal: true

require "rails_helper"

RSpec.describe DunningCampaigns::OrganizationProcessJob, type: :job do
  let(:organization) { build :organization }

  before do
    allow(DunningCampaigns::OrganizationProcessService).to receive(:call!)
  end

  context "without Lago Premium license" do
    it "calls DunningCampaigns::OrganizationProcessService" do
      described_class.perform_now(organization)

      expect(DunningCampaigns::OrganizationProcessService).not_to have_received(:call!).with(organization)
    end
  end

  context "with Lago Premium license" do
    around { |test| lago_premium!(&test) }

    it "calls DunningCampaigns::OrganizationProcessService" do
      described_class.perform_now(organization)

      expect(DunningCampaigns::OrganizationProcessService).to have_received(:call!).with(organization)
    end
  end
end
