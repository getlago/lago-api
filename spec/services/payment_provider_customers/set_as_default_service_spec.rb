# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::SetAsDefaultService do
  subject(:set_as_default_service) { described_class.new(payment_provider_customer:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  let(:stripe_customer) { create(:stripe_customer, customer:, organization:, code: "stripe_eu", is_default: true) }
  let(:gocardless_customer) { create(:gocardless_customer, customer:, organization:, code: "gocardless_eu", is_default: false) }

  let(:payment_provider_customer) { gocardless_customer }

  before do
    stripe_customer
    gocardless_customer
  end

  describe "#call" do
    it "sets the target as default and clears the customer's other payment connections" do
      result = set_as_default_service.call

      expect(result).to be_success
      expect(gocardless_customer.reload.is_default).to be(true)
      expect(stripe_customer.reload.is_default).to be(false)
    end

    it "runs under the per-customer payment_provider_customer advisory lock" do
      allow(Customers::LockService).to receive(:call).and_call_original

      set_as_default_service.call

      expect(Customers::LockService).to have_received(:call).with(customer:, scope: :payment_provider_customer)
    end

    context "when the connection is already default" do
      let(:payment_provider_customer) { stripe_customer }

      it "is a no-op and returns the record" do
        result = set_as_default_service.call

        expect(result).to be_success
        expect(result.payment_provider_customer).to eq(stripe_customer)
        expect(gocardless_customer.reload.is_default).to be(false)
      end
    end

    context "when the payment_provider_customer is nil" do
      let(:payment_provider_customer) { nil }

      it "returns a not found failure" do
        result = set_as_default_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
      end
    end

    context "when the advisory lock cannot be acquired" do
      before do
        allow(Customers::LockService).to receive(:call).and_raise(BaseLockService::FailedToAcquireLock)
      end

      it "returns a lock acquisition failure and leaves defaults unchanged" do
        result = set_as_default_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::LockAcquisitionFailure)
        expect(gocardless_customer.reload.is_default).to be(false)
        expect(stripe_customer.reload.is_default).to be(true)
      end
    end
  end
end
