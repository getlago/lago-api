# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::RealtimeRefreshService do
  subject(:service_result) do
    described_class.call(organization_id: organization.id, customer_id: customer.id, wallet_codes:)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:wallet_codes) { [] }

  let(:refresh_result) do
    Customers::RefreshWalletsService::Result.new.tap { |r| r.wallets = [] }
  end

  before do
    allow(Customers::RefreshWalletsService).to receive(:call).and_return(refresh_result)
  end

  context "with an active wallet" do
    before { create(:wallet, customer:, organization:) }

    it "refreshes the customer wallets" do
      expect(service_result).to be_success
      expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
    end

    context "with unknown targeted wallet codes" do
      let(:wallet_codes) { ["nope"] }

      it "still refreshes (the cascade covers every wallet)" do
        expect(service_result).to be_success
        expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
      end
    end
  end

  context "without an active wallet" do
    it "does nothing" do
      expect(service_result).to be_success
      expect(Customers::RefreshWalletsService).not_to have_received(:call)
    end
  end

  context "with an unknown customer" do
    subject(:service_result) do
      described_class.call(organization_id: organization.id, customer_id: SecureRandom.uuid)
    end

    it "does nothing" do
      expect(service_result).to be_success
      expect(Customers::RefreshWalletsService).not_to have_received(:call)
    end
  end
end
