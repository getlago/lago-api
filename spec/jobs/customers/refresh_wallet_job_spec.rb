# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::RefreshWalletJob do
  describe "#perform" do
    subject { described_class.perform_now(customer) }

    let(:customer) { create(:customer, awaiting_wallet_refresh:) }
    let(:organization) { customer.organization }
    let(:result) { BaseService::Result.new }

    before do
      create(:wallet, customer:, organization:)

      allow(Customers::RefreshWalletsService).to receive(:call).with(customer:).and_return(result)
    end

    context "when customer is not awaiting wallet refresh" do
      let(:awaiting_wallet_refresh) { false }

      it "does not call the Customers::RefreshWalletsService service" do
        subject
        expect(Customers::RefreshWalletsService).not_to have_received(:call)
      end
    end

    context "when customer is awaiting wallet refresh" do
      let(:awaiting_wallet_refresh) { true }

      context "when refresh customer's wallets succeeds" do
        it "calls the Customers::RefreshWalletsService service" do
          subject
          expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
        end
      end

      context "when refresh customer's wallets fails" do
        let(:result) { BaseService::Result.new.validation_failure!(errors: {tax_error: "error"}) }

        it "fails with an error" do
          expect { subject }.to raise_error(BaseService::ValidationFailure)
        end
      end
    end
  end
end
