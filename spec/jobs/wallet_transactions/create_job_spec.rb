# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactions::CreateJob, type: :job do
  subject(:create_job) { described_class }

  let(:wallet_transaction_create_service) { instance_double(WalletTransactions::CreateService) }

  it "calls the WalletTransactions::CreateService" do
    allow(WalletTransactions::CreateService).to receive(:new)
      .and_return(wallet_transaction_create_service)
    allow(wallet_transaction_create_service).to receive(:create)

    described_class.perform_now(
      organization_id: "123456",
      wallet_id: "123456",
      paid_credits: "1.00",
      granted_credits: "1.00",
      source: "manual"
    )

    expect(wallet_transaction_create_service).to have_received(:create).with(
      organization_id: "123456",
      wallet_id: "123456",
      paid_credits: "1.00",
      granted_credits: "1.00",
      source: "manual"
    )
  end
end
