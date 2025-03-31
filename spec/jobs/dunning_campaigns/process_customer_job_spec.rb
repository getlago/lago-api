# frozen_string_literal: true

require "rails_helper"

RSpec.describe DunningCampaigns::ProcessCustomerJob, type: :job do
  let(:customer) { build :customer }

  before do
    allow(DunningCampaigns::CheckCustomerService).to receive(:call!)
    allow(DunningCampaigns::ProcessAttemptJob).to receive(:perform_later)
  end

  context "without Lago Premium license" do
    it "calls DunningCampaigns::OrganizationProcessService" do
      described_class.perform_now(customer)

      expect(DunningCampaigns::CheckCustomerService).not_to have_received(:call!)
      expect(DunningCampaigns::ProcessAttemptJob).not_to have_received(:perform_later)
    end
  end

  context "with Lago Premium license" do
    around { |test| lago_premium!(&test) }

    it "calls DunningCampaigns::OrganizationProcessService" do
      threshold = build :dunning_campaign_threshold
      result = instance_double(DunningCampaigns::CheckCustomerService::Result,
        should_process_customer: true,
        customer:,
        threshold:)

      allow(DunningCampaigns::CheckCustomerService).to receive(:call!).and_return(result)

      described_class.perform_now(customer)

      expect(DunningCampaigns::ProcessAttemptJob).to have_received(:perform_later)
        .with(customer:, dunning_campaign_threshold: threshold)
    end

    context "when customer should not be processed" do
      it "does not call DunningCampaigns::ProcessAttemptJob" do
        result = instance_double(DunningCampaigns::CheckCustomerService::Result,
          should_process_customer: false,
          customer:)

        allow(DunningCampaigns::CheckCustomerService).to receive(:call!).and_return(result)

        described_class.perform_now(customer)

        expect(DunningCampaigns::ProcessAttemptJob).not_to have_received(:perform_later)
      end
    end
  end
end
