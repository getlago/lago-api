# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DunningCampaigns::BulkProcessJob, type: :job do
  let(:result) { BaseService::Result.new }

  before do
    allow(DunningCampaigns::BulkProcessService)
      .to receive(:call)
      .and_return(result)
  end

  context "when premium features are enabled" do
    around { |test| lago_premium!(&test) }

    it "calls DunningCampaigns::BulkProcessService service" do
      described_class.perform_now

      expect(DunningCampaigns::BulkProcessService)
        .to have_received(:call)
    end
  end

  it "does nothing" do
    described_class.perform_now

    expect(DunningCampaigns::BulkProcessService)
      .not_to have_received(:call)
  end
end
