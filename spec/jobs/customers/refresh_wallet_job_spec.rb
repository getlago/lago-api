# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::RefreshWalletJob do
  subject(:job) { described_class }

  let(:customer) { create(:customer) }

  before do
    allow(Customers::RefreshWalletsService).to receive(:call!).and_return(Customers::RefreshWalletsService::Result.new)
  end

  describe "#perform" do
    # The name this job was enqueued under before the rename, kept so a queued payload still
    # deserializes across the deploy.
    it "refreshes the customer through the renamed job" do
      job.perform_now(customer)

      expect(Customers::RefreshWalletsService).to have_received(:call!).with(customer:, force: false)
    end
  end
end
