# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WalletTransactions::CreateJob, type: :job do
  subject(:create_job) { described_class }

  let(:organization) { create(:organization) }
  let(:wallet_transaction_create_service) { instance_double(WalletTransactions::CreateService) }

  it 'calls the WalletTransactions::CreateService' do
    allow(WalletTransactions::CreateService).to receive(:call)

    described_class.perform_now(
      organization_id: organization.id,
      params: {
        wallet_id: '123456',
        paid_credits: '1.00',
        granted_credits: '1.00',
        source: 'manual',
      },
    )

    expect(WalletTransactions::CreateService).to have_received(:call).with(
      organization:,
      params: {
        wallet_id: '123456',
        paid_credits: '1.00',
        granted_credits: '1.00',
        source: 'manual',
      },
    )
  end
end
