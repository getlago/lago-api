# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::RefreshWalletService do
  subject(:service) { described_class.call(customer:, **options) }

  let(:customer) { create(:customer, awaiting_wallet_refresh:) }
  let(:organization) { customer.organization }
  let(:awaiting_wallet_refresh) { true }
  let(:options) { {} }
  let(:refresh_result) { Customers::RefreshWalletsService::Result.new }

  before do
    allow(Customers::RefreshWalletsService).to receive(:call).with(customer:).and_return(refresh_result)
  end

  describe "#call" do
    it "refreshes the customer's wallets" do
      service

      expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
    end

    context "when the customer is not awaiting a wallet refresh" do
      let(:awaiting_wallet_refresh) { false }

      it "does not refresh" do
        service

        expect(Customers::RefreshWalletsService).not_to have_received(:call)
      end

      context "when the refresh is forced" do
        let(:options) { {force: true} }

        it "refreshes the customer's wallets" do
          service

          expect(Customers::RefreshWalletsService).to have_received(:call).with(customer:)
        end
      end
    end

    context "when a tax_error error_detail already exists" do
      before { create(:error_detail, owner: customer, organization:, error_code: :tax_error) }

      it "does not refresh" do
        service

        expect(Customers::RefreshWalletsService).not_to have_received(:call)
      end
    end

    context "when the refresh fails with a tax error on the customer's address" do
      let(:refresh_result) do
        Customers::RefreshWalletsService::Result.new.validation_failure!(errors: {tax_error: ["customerAddressCouldNotResolve"]})
      end

      it "creates a tax_error error_detail on the customer" do
        expect { service }.to change { customer.error_details.tax_error.count }.by(1)
      end

      it "does not re-raise the error" do
        expect { service }.not_to raise_error
      end
    end

    context "when the refresh fails with an unknown tax error" do
      let(:refresh_result) do
        Customers::RefreshWalletsService::Result.new.validation_failure!(errors: {tax_error: ["failure"]})
      end

      it "re-raises the error without creating an error_detail" do
        expect { service }.to raise_error(BaseService::ValidationFailure).and not_change { customer.error_details.count }
      end
    end

    context "when the refresh fails with a non-tax error" do
      let(:refresh_result) do
        Customers::RefreshWalletsService::Result.new.validation_failure!(errors: {other_error: ["something"]})
      end

      it "re-raises the error" do
        expect { service }.to raise_error(BaseService::ValidationFailure)
      end
    end

    context "when another lane holds the customer's refresh lock", transaction: false do
      let(:options) { {lock_timeout_seconds: 0} }

      around do |test|
        with_advisory_lock("customer-#{customer.id}-wallet_refresh", lock_released_after: 2.seconds) do
          test.run
        end
      end

      it "raises rather than refreshing concurrently" do
        expect { service }.to raise_error(BaseLockService::FailedToAcquireLock)
        expect(Customers::RefreshWalletsService).not_to have_received(:call)
      end
    end
  end
end
