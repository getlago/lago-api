# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessWalletAlertsJob do
  it_behaves_like "a configurable queue", "alerts_high_priority", "SIDEKIQ_ALERTS" do
    let(:arguments) { create(:wallet) }
  end

  describe "#perform" do
    let(:wallet) { create(:wallet) }

    before do
      allow(UsageMonitoring::ProcessWalletAlertsService).to receive(:call!)
    end

    context "when premium", :premium do
      it "calls the ProcessWalletAlertsService with the wallet" do
        described_class.perform_now(wallet)
        expect(UsageMonitoring::ProcessWalletAlertsService).to have_received(:call!).with(wallet:)
      end
    end

    context "when freemium" do
      it "does not call the ProcessWalletAlertsService with the wallet" do
        described_class.perform_now(wallet)
        expect(UsageMonitoring::ProcessWalletAlertsService).not_to have_received(:call!)
      end
    end
  end
end
