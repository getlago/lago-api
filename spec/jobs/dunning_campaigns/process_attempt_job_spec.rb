# frozen_string_literal: true

require "rails_helper"

RSpec.describe DunningCampaigns::ProcessAttemptJob do
  let(:result) { BaseService::Result.new }
  let(:customer) { build :customer }
  let(:dunning_campaign_threshold) { build :dunning_campaign_threshold }

  before do
    allow(DunningCampaigns::ProcessAttemptService)
      .to receive(:call)
      .and_return(result)
  end

  it "calls DunningCampaigns::ProcessAttemptService" do
    described_class.perform_now(customer:, dunning_campaign_threshold:)

    expect(DunningCampaigns::ProcessAttemptService)
      .to have_received(:call)
      .with(customer:, dunning_campaign_threshold:)
  end
end
