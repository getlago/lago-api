# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::RefreshWalletJob do
  describe "#perform" do
    subject { described_class.perform_now(customer) }

    let(:customer) { create(:customer, awaiting_wallet_refresh:) }
    let(:organization) { customer.organization }
    let(:result) { BaseService::Result.new }

    before do
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

      context "when refresh customer's wallets fails with a tax error" do
        let(:result) { BaseService::Result.new.validation_failure!(errors: {tax_error: ["customerAddressCouldNotResolve"]}) }

        it "does not raise an error" do
          expect { subject }.not_to raise_error
        end
      end

      context "when refresh customer's wallets fails with a non-tax error" do
        let(:result) { BaseService::Result.new.validation_failure!(errors: {base: ["some_other_error"]}) }

        it "raises an error" do
          expect { subject }.to raise_error(BaseService::ValidationFailure)
        end
      end
    end
  end
end
