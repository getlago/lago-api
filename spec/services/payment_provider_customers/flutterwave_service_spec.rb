# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::FlutterwaveService do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization: organization) }
  let(:flutterwave_provider) { create(:flutterwave_provider, organization: organization) }
  let(:flutterwave_customer) { create(:flutterwave_customer, customer: customer, payment_provider: flutterwave_provider) }

  describe ".call(:create)" do
    it "returns success with the flutterwave customer" do
      result = described_class.call(:create, flutterwave_customer)

      expect(result).to be_success
      expect(result.flutterwave_customer).to eq(flutterwave_customer)
    end
  end

  describe ".call(:update)" do
    it "returns success" do
      result = described_class.call(:update, flutterwave_customer)

      expect(result).to be_success
    end
  end

  describe ".call(:generate_checkout_url)" do
    it "returns not allowed failure" do
      result = described_class.call(:generate_checkout_url, flutterwave_customer)

      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      expect(result.error.code).to eq("feature_not_supported")
    end

    context "when send_webhook is false" do
      it "returns not allowed failure" do
        result = described_class.call(:generate_checkout_url, flutterwave_customer, send_webhook: false)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("feature_not_supported")
      end
    end
  end

  describe "private methods" do
    describe "#customer" do
      it "delegates to flutterwave_customer" do
        service = described_class.new
        service.instance_variable_set(:@flutterwave_customer, flutterwave_customer)

        expect(service.send(:customer)).to eq(customer)
      end
    end
  end
end
