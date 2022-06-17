# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviderCustomers::CreateService, type: :service do
  let(:create_service) { described_class.new(customer) }

  let(:customer) { create(:customer) }

  let(:create_params) do
    { provider_customer_id: 'stripe_id' }
  end

  let(:stripe_provider) { create(:stripe_provider, organization: customer.organization) }

  describe '.create' do
    it 'creates a payment_provider_customer' do
      result = create_service.create(
        customer_class: PaymentProviderCustomers::StripeCustomer,
        payment_provider_id: stripe_provider.id,
        params: create_params,
      )

      expect(result).to be_success
      expect(result.provider_customer).to be_present
      expect(result.provider_customer.provider_customer_id).to eq('stripe_id')
    end
  end
end
