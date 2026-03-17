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

      context "when a tax_error error_detail already exists" do
        before do
          create(:error_detail, owner: customer, organization:, error_code: :tax_error)
        end

        it "does not call the Customers::RefreshWalletsService service" do
          subject
          expect(Customers::RefreshWalletsService).not_to have_received(:call)
        end
      end

      context "when refresh customer's wallets fails with a tax error" do
        let(:result) { BaseService::Result.new.validation_failure!(errors: {tax_error: ["customerAddressCouldNotResolve"]}) }

        it "creates a tax_error error_detail on the customer" do
          expect { subject }.to change { customer.error_details.tax_error.count }.by(1)
        end

        it "does not re-raise the error" do
          expect { subject }.not_to raise_error
        end

        context "when the tax error is not related to the customer's address" do
          let(:result) { BaseService::Result.new.validation_failure!(errors: {tax_error: ["failure"]}) }

          it "does not create an error_detail and re-raises the error" do
            expect { subject }.to raise_error(BaseService::ValidationFailure).and not_change { customer.error_details.count }
          end
        end
      end

      context "when refresh customer's wallets fails with a non-tax error" do
        let(:result) { BaseService::Result.new.validation_failure!(errors: {other_error: ["something"]}) }

        it "re-raises the error" do
          expect { subject }.to raise_error(BaseService::ValidationFailure)
        end
      end
    end
  end
end
