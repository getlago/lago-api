# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Paystack::Customers::CreateService do
  subject(:result) do
    described_class.call(
      customer:,
      payment_provider_id: payment_provider.id,
      params:,
      async:
    )
  end

  let(:organization) { create(:organization) }
  let(:payment_provider) { create(:paystack_provider, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:params) { {} }
  let(:async) { true }

  it "creates a Paystack provider customer" do
    expect { result }.to change(PaymentProviderCustomers::PaystackCustomer, :count).by(1)
    expect(result.provider_customer).to have_attributes(
      customer:,
      organization:,
      payment_provider:
    )
  end

  context "when sync with provider is requested" do
    let(:params) { {sync_with_provider: true} }

    it "enqueues provider customer creation" do
      result

      expect(PaymentProviderCustomers::PaystackCreateJob)
        .to have_been_enqueued.with(result.provider_customer)
    end
  end

  context "when a provider customer id is supplied for an existing customer" do
    let!(:provider_customer) { create(:paystack_customer, customer:, organization:, payment_provider:, provider_customer_id: nil) }
    let(:params) { {provider_customer_id: "CUS_test"} }

    it "enqueues checkout URL generation" do
      result

      expect(result.provider_customer).to eq(provider_customer)
      expect(PaymentProviderCustomers::PaystackCheckoutUrlJob)
        .to have_been_enqueued.with(provider_customer)
    end
  end
end
