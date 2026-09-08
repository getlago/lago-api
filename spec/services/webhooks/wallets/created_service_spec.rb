# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Wallets::CreatedService do
  subject(:webhook_service) { described_class.new(object: wallet) }

  let(:wallet) { create(:wallet, :with_purchase_order_number, balance_cents: 999_00) }

  describe ".call" do
    it_behaves_like "creates webhook", "wallet.created", "wallet", {
      "balance_cents" => 999_00,
      "purchase_order_number" => "PO-123",
      "created_at" => String,
      "terminated_at" => nil,
      "recurring_transaction_rules" => []
    }
  end
end
