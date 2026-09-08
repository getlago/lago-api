# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Wallets::DepletedOngoingBalanceService do
  subject(:webhook_service) { described_class.new(object: wallet) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, :with_purchase_order_number, customer:) }

  describe ".call" do
    it_behaves_like "creates webhook", "wallet.depleted_ongoing_balance", "wallet", {
      "purchase_order_number" => "PO-123"
    }
  end
end
