# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviderCustomers::CreateService, type: :service do
  let(:create_service) { described_class.new(customer) }

  let(:customer) { create(:customer) }
  let(:stripe_provider) { create(:stripe_provider, organization: customer.organization) }

  let(:create_params) do
    { provider_customer_id: 'id', sync_with_provider: true }
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
      expect(result.provider_customer.provider_customer_id).to eq('id')
    end

    context 'when no provider customer id and should create on service' do
      let(:create_params) do
        { provider_customer_id: nil, sync_with_provider: true }
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

    context 'when no gocardless provider customer id and should create on service' do
      let(:create_params) do
        { provider_customer_id: nil, sync_with_provider: true }
      end

      let(:gocardless_provider) do
        create(
          :gocardless_provider,
          organization: customer.organization,
        )
      end

      it 'enqueues a job to create the customer on the provider' do
        expect do
          create_service.create_or_update(
            customer_class: PaymentProviderCustomers::GocardlessCustomer,
            payment_provider_id: gocardless_provider.id,
            params: create_params,
          )
        end.to have_enqueued_job(PaymentProviderCustomers::GocardlessCreateJob)
      end
    end

    context 'when removing the provider customer id and should create on service' do
      let(:create_params) do
        { provider_customer_id: nil, sync_with_provider: true }
      end

      let(:stripe_customer) do
        create(
          :stripe_customer,
          customer: customer,
          payment_provider: stripe_provider,
        )
      end

      before { stripe_customer }

      it 'updates the provider customer' do
        expect do
          result = create_service.create_or_update(
            customer_class: PaymentProviderCustomers::StripeCustomer,
            payment_provider_id: stripe_provider.id,
            params: create_params,
          )

          aggregate_failures do
            expect(result).to be_success

            expect(result.provider_customer.provider_customer_id).to be_nil
          end
        end.not_to have_enqueued_job(PaymentProviderCustomers::StripeCreateJob)
      end
    end
  end
end
