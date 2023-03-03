# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Customers::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }
  let(:stripe_provider) { create(:stripe_provider, organization: organization) }

  let(:mutation) do
    <<~GQL
      mutation($input: UpdateCustomerInput!) {
        updateCustomer(input: $input) {
          id,
          name,
          externalId
          paymentProvider
          currency
          timezone
          canEditAttributes
          invoiceGracePeriod
          providerCustomer { id, providerCustomerId }
          billingConfiguration { id, documentLocale }
          metadata { id, key, value, displayInInvoice }
        }
      }
    GQL
  end

  it 'updates a customer' do
    stripe_provider
    external_id = SecureRandom.uuid

    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: customer.id,
          name: 'Updated customer',
          externalId: external_id,
          paymentProvider: 'stripe',
          currency: 'EUR',
          providerCustomer: {
            providerCustomerId: 'cu_12345',
          },
          billingConfiguration: {
            documentLocale: 'fr',
          },
          metadata: [
            {
              key: 'test-key',
              value: 'value',
              displayInInvoice: true,
            },
          ],
        },
      },
    )

    result_data = result['data']['updateCustomer']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('Updated customer')
      expect(result_data['externalId']).to eq(external_id)
      expect(result_data['paymentProvider']).to eq('stripe')
      expect(result_data['currency']).to eq('EUR')
      expect(result_data['timezone']).to be_nil
      expect(result_data['invoiceGracePeriod']).to be_nil
      expect(result_data['providerCustomer']['id']).to be_present
      expect(result_data['providerCustomer']['providerCustomerId']).to eq('cu_12345')
      expect(result_data['billingConfiguration']['documentLocale']).to eq('fr')
      expect(result_data['billingConfiguration']['id']).to eq("#{customer.id}-c0nf")
      expect(result_data['metadata'][0]['key']).to eq('test-key')
    end
  end

  context 'with premium feature' do
    around { |test| lago_premium!(&test) }

    it 'updates a customer' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            id: customer.id,
            externalId: SecureRandom.uuid,
            name: 'Updated customer',
            timezone: 'TZ_EUROPE_PARIS',
            invoiceGracePeriod: 2,
          },
        },
      )

      result_data = result['data']['updateCustomer']

      aggregate_failures do
        expect(result_data['timezone']).to eq('TZ_EUROPE_PARIS')
        expect(result_data['invoiceGracePeriod']).to eq(2)
      end
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: customer.id,
            name: 'Updated customer',
            externalId: SecureRandom.uuid,
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
