# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::TerminateService, type: :service do
  subject(:terminate_service) { described_class.new(wallet:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:) }

  describe "#call" do
    before do
      subscription
      wallet
    end

    it "terminates the wallet" do
      result = terminate_service.call

      expect(result).to be_success
      expect(result.wallet).to be_terminated
    end

    it "sends a `wallet.terminated` webhook" do
      expect { terminate_service.call }.to have_enqueued_job(SendWebhookJob).with("wallet.terminated", Wallet)
    end

    context "when wallet is already terminated" do
      before { wallet.mark_as_terminated! }

      it "does not impact the wallet" do
        wallet.reload
        terminated_at = wallet.terminated_at
        result = terminate_service.call

        expect(result).to be_success
        expect(result.wallet).to be_terminated
        expect(result.wallet.terminated_at).to eq(terminated_at)
      end

      it "does not send the `wallet.terminated` webhook" do
        expect { terminate_service.call }.not_to have_enqueued_job(SendWebhookJob)
      end
    end
  end
end
