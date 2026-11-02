# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyUsages::ComputeContractJob do
  subject(:compute_job) { described_class }

  let(:customer) { create(:customer, timezone: "Europe/Paris") }
  let(:contract) { create(:contract, customer:) }
  let(:timestamp) { Time.current }

  describe ".perform" do
    it "delegates to DailyUsages::ComputeContractService" do
      allow(DailyUsages::ComputeContractService).to receive(:call!)
        .with(contract:, timestamp:)
        .and_return(DailyUsages::ComputeContractService::Result.new)

      compute_job.perform_now(contract, timestamp:)

      expect(DailyUsages::ComputeContractService).to have_received(:call!)
        .with(contract:, timestamp:).once
    end
  end

  describe "#lock_key_arguments" do
    it "returns the contract id and the date in the customer timezone" do
      # 23:00 UTC = 00:00+01:00 (Jan 16 in Paris)
      job = described_class.new(contract, timestamp: Time.zone.parse("2024-01-15 23:00:00 UTC"))

      expect(job.lock_key_arguments).to eq([contract.id, Date.new(2024, 1, 16)])
    end
  end
end
