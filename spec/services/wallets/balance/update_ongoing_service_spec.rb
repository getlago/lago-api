# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::Balance::UpdateOngoingService do
  subject(:update_service) { described_class.new(wallet:, update_params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) do
    create(
      :wallet,
      customer:,
      balance_cents: 1000,
      ongoing_balance_cents: 800,
      ongoing_usage_balance_cents: 200,
      credits_balance: 10.0,
      credits_ongoing_balance: 8.0,
      credits_ongoing_usage_balance: 2.0,
      ready_to_be_refreshed: true
    )
  end
  let(:update_params) do
    {
      ongoing_usage_balance_cents: 550,
      credits_ongoing_usage_balance: 5.5,
      ongoing_balance_cents: 450,
      credits_ongoing_balance: 4.5,
      ready_to_be_refreshed: false,
      depleted_ongoing_balance:
    }
  end
  let(:depleted_ongoing_balance) { false }

  before { wallet }

  describe "#call" do
    it "updates wallet balance" do
      freeze_time do
        create(:invoice, :draft, customer:, organization:, total_amount_cents: 150)

        expect { update_service.call }
          .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(550)
          .and change(wallet, :credits_ongoing_usage_balance).from(2.0).to(5.5)
          .and change(wallet, :ongoing_balance_cents).from(800).to(450)
          .and change(wallet, :credits_ongoing_balance).from(8.0).to(4.5)
          .and change(wallet, :ready_to_be_refreshed).from(true).to(false)
          .and change(wallet, :last_ongoing_balance_sync_at).from(nil).to(Time.current)
          .and not_change(wallet, :last_balance_sync_at)

        expect(wallet).not_to be_depleted_ongoing_balance
      end
    end

    context "when depleted ongoing balance" do
      let(:depleted_ongoing_balance) { true }

      it "sends depleted_ongoing_balance webhook" do
        expect { update_service.call }
          .to have_enqueued_job(SendWebhookJob)
          .with("wallet.depleted_ongoing_balance", Wallet)
      end
    end
  end
end
