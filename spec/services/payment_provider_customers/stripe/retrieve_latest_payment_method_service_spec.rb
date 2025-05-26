# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::Stripe::RetrieveLatestPaymentMethodService, type: :service do
  subject { described_class.new(provider_customer:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:provider_customer_id) { "cus_Rw5Qso78STEap3" }
  let(:provider_customer) { create(:stripe_customer, customer:, provider_customer_id:, payment_provider: create(:stripe_provider, organization:), payment_method_id: nil) }

  describe "#call" do
    context "when customer has a default payment method in Stripe" do
      it do
        stub_request(:get, %r{/v1/customers/#{provider_customer_id}$}).and_return(
          status: 200, body: get_stripe_fixtures("customer_with_default_payment_method.json")
        )

        result = subject.call
        expect(result.payment_method_id).to eq "pm_1R2DFsQ8iJWBZFaMw3LLbR0r"
      end
    end

    context "when customer has payment method in Stripe but no default" do
      it do
        stub_request(:get, %r{/v1/customers/#{provider_customer_id}$}).and_return(
          status: 200, body: get_stripe_fixtures("customer_no_default_payment_method.json")
        )
        stub_request(:get, %r{/v1/customers/#{provider_customer_id}/payment_methods}).and_return(
          status: 200, body: get_stripe_fixtures("customer_list_payment_methods.json")
        )

        result = subject.call
        expect(result.payment_method_id).to eq "pm_1R2EmOQ8iJWBZFaMKJHOwcvP"
      end
    end

    context "when customer has no payment method in Stripe" do
      it do
        stub_request(:get, %r{/v1/customers/#{provider_customer_id}$}).and_return(
          status: 200, body: get_stripe_fixtures("customer_no_default_payment_method.json")
        )
        stub_request(:get, %r{/v1/customers/#{provider_customer_id}/payment_methods}).and_return(
          status: 200, body: get_stripe_fixtures("customer_list_no_payment_methods.json")
        )

        result = subject.call
        expect(result.payment_method_id).to be_nil
      end
    end
  end
end
