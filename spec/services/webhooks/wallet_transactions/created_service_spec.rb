# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::WalletTransactions::CreatedService do
  subject(:webhook_service) { described_class.new(object: wallet_transaction) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, customer:) }
  let(:wallet_transaction) { create(:wallet_transaction, wallet:) }

  describe '.call' do
    it_behaves_like 'creates webhook', 'wallet_transaction.created', 'wallet_transaction'
  end
end
