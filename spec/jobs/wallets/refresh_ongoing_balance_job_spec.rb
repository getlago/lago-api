# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::RefreshOngoingBalanceJob, type: :job do
  let(:wallet) { create(:wallet) }
  let(:result) { BaseService::Result.new }

  let(:refresh_service) do
    instance_double(Wallets::Balance::RefreshOngoingService)
  end

  it "delegates to the RefreshOngoingBalance service" do
    allow(Wallets::Balance::RefreshOngoingService).to receive(:new).with(wallet:).and_return(refresh_service)
    allow(refresh_service).to receive(:call).and_return(result)

    described_class.perform_now(wallet)

    expect(Wallets::Balance::RefreshOngoingService).to have_received(:new)
    expect(refresh_service).to have_received(:call)
  end
end
