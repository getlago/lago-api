# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::ExpireJob do
  subject(:expire_job) { described_class }

  let(:wallet) { create(:wallet) }

  before { allow(Wallets::ExpireService).to receive(:call!) }

  it "expires the wallet" do
    expire_job.perform_now(wallet)

    expect(Wallets::ExpireService).to have_received(:call!).with(wallet:)
  end
end
