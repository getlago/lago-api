# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactions::CreateJob, type: :job do
  subject(:create_job) { described_class }

  let(:organization) { create(:organization) }
  let(:wallet) { create(:wallet) }
  let(:wallet_transaction_create_service) { instance_double(WalletTransactions::CreateService) }
  let(:params) do
    {
      wallet_id: wallet.id,
      paid_credits: "1.00",
      granted_credits: "1.00",
      source: "manual"
    }
  end

  it "calls the WalletTransactions::CreateService" do
    allow(WalletTransactions::CreateService).to receive(:call!)

    described_class.perform_now(organization_id: organization.id, params:)

    expect(WalletTransactions::CreateService).to have_received(:call!).with(organization:, params:)
  end
end
