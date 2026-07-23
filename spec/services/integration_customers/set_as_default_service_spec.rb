# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCustomers::SetAsDefaultService do
  subject(:set_as_default_service) { described_class.new(integration_customer:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  # accounting category
  let(:netsuite_customer) { create(:netsuite_customer, customer:, organization:, category: "accounting", is_default: true) }
  let(:xero_customer) { create(:xero_customer, customer:, organization:, category: "accounting", is_default: false) }
  # tax category (different category, must stay untouched)
  let(:anrok_customer) { create(:anrok_customer, customer:, organization:, category: "tax", is_default: true) }

  let(:integration_customer) { xero_customer }

  before do
    netsuite_customer
    xero_customer
    anrok_customer
  end

  describe "#call" do
    it "sets the target as default and clears same-category siblings" do
      result = set_as_default_service.call

      expect(result).to be_success
      expect(xero_customer.reload.is_default).to be(true)
      expect(netsuite_customer.reload.is_default).to be(false)
    end

    it "does not touch defaults in other categories" do
      set_as_default_service.call

      expect(anrok_customer.reload.is_default).to be(true)
    end

    it "runs under the per-customer integration_customer advisory lock" do
      allow(Customers::LockService).to receive(:call).and_call_original

      set_as_default_service.call

      expect(Customers::LockService).to have_received(:call).with(customer:, scope: :integration_customer)
    end

    context "when the connection is already default" do
      let(:integration_customer) { netsuite_customer }

      it "is a no-op and returns the record" do
        result = set_as_default_service.call

        expect(result).to be_success
        expect(result.integration_customer).to eq(netsuite_customer)
        expect(xero_customer.reload.is_default).to be(false)
      end
    end

    context "when the integration_customer is nil" do
      let(:integration_customer) { nil }

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
        expect(xero_customer.reload.is_default).to be(false)
        expect(netsuite_customer.reload.is_default).to be(true)
      end
    end
  end
end
