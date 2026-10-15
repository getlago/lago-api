# frozen_string_literal: true

require "rails_helper"

RSpec.describe DunningCampaigns::ProcessCustomerJob do
  let(:customer) { create(:customer) }

  before do
    allow(DunningCampaigns::ProcessCustomerService).to receive(:call!)
  end

  it "calls DunningCampaigns::ProcessCustomerService" do
    described_class.perform_now(customer)

    expect(DunningCampaigns::ProcessCustomerService)
      .to have_received(:call!)
      .with(customer:)
  end
end
