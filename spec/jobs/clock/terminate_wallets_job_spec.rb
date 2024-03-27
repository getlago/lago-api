# frozen_string_literal: true

require "rails_helper"

describe Clock::TerminateWalletsJob, job: true do
  let(:to_expire_wallet) do
    create(
      :wallet,
      status: "active",
      expiration_at: Time.zone.now - 40.days
    )
  end

  let(:to_keep_active_wallet) do
    create(
      :wallet,
      status: "active",
      expiration_at: Time.zone.now + 40.days
    )
  end

  before do
    to_expire_wallet
    to_keep_active_wallet
  end

  it "terminates the expired wallets" do
    described_class.perform_now

    expect(to_expire_wallet.reload.status).to eq("terminated")
    expect(to_keep_active_wallet.reload.status).to eq("active")
  end
end
