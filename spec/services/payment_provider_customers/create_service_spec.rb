# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviderCustomers::CreateService, type: :service do
  let(:create_service) { described_class.new(customer) }

  let(:customer) { create(:customer) }
  let(:stripe_provider) { create(:stripe_provider, organization: customer.organization) }

  let(:create_params) do
    { provider_customer_id: 'stripe_id' }
  end

  describe '.create_or_update' do
    it 'creates a payment_provider_customer' do
      result = create_service.create_or_update(
        customer_class: PaymentProviderCustomers::StripeCustomer,
        payment_provider_id: stripe_provider.id,
        params: create_params,
      )

      expect(result).to be_success
      expect(result.provider_customer).to be_present
      expect(result.provider_customer.provider_customer_id).to eq('stripe_id')
    end

    context 'when no provider customer id and should create on service' do
      let(:create_params) do
        { provider_customer_id: nil }
      end

      let(:stripe_provider) do
        create(
          :stripe_provider,
          organization: customer.organization,
          create_customers: true,
        )
      end

      it 'enqueues a job to create the customer on the provider' do
        expect do
          create_service.create_or_update(
            customer_class: PaymentProviderCustomers::StripeCustomer,
            payment_provider_id: stripe_provider.id,
            params: create_params,
          )
        end.to have_enqueued_job(PaymentProviderCustomers::StripeCreateJob)
      end
    end
  end
end
