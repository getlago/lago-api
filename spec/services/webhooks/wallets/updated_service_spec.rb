# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Wallets::UpdatedService do
  subject(:webhook_service) { described_class.new(object: wallet) }

  let(:wallet) { create(:wallet, :with_purchase_order_number) }

  describe ".call" do
    it_behaves_like "creates webhook", "wallet.updated", "wallet", {
      "purchase_order_number" => "PO-123",
      "recurring_transaction_rules" => []
    }
  end
end
