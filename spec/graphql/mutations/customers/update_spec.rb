# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Customers::Update, type: :graphql do
  let(:required_permissions) { 'customers:update' }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:stripe_provider) { create(:stripe_provider, organization:) }
  let(:tax) { create(:tax, organization:) }

  let(:mutation) do
    <<~GQL
      mutation($input: UpdateCustomerInput!) {
        updateCustomer(input: $input) {
          id
          name
          taxIdentificationNumber
          externalId
          paymentProvider
          currency
          timezone
          netPaymentTerm
          canEditAttributes
          invoiceGracePeriod
          providerCustomer { id, providerCustomerId, providerPaymentMethods }
          billingConfiguration { id, documentLocale }
          metadata { id, key, value, displayInInvoice }
          taxes { code }
        }
      }
    GQL
  end

  let(:body) do
    {
      object: 'event',
      data: {},
    }
  end

  before do
    stub_request(:post, 'https://api.stripe.com/v1/checkout/sessions')
      .to_return(status: 200, body: body.to_json, headers: {})

    allow(Stripe::Customer).to receive(:update).and_return(BaseService::Result.new)
  end

  it_behaves_like 'requires current user'
  it_behaves_like 'requires permission', 'customers:update'

  it 'updates a customer' do
    stripe_provider
    external_id = SecureRandom.uuid

    result = execute_graphql(
      current_user: membership.user,
      permissions: required_permissions,
      query: mutation,
      variables: {
        input: {
          id: customer.id,
          name: 'Updated customer',
          taxIdentificationNumber: '2246',
          externalId: external_id,
          paymentProvider: 'stripe',
          currency: 'EUR',
          netPaymentTerm: 3,
          providerCustomer: {
            providerCustomerId: 'cu_12345',
            providerPaymentMethods: %w[card sepa_debit],
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
          taxCodes: [tax.code],
        },
      },
    )

    result_data = result['data']['updateCustomer']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('Updated customer')
      expect(result_data['taxIdentificationNumber']).to eq('2246')
      expect(result_data['externalId']).to eq(external_id)
      expect(result_data['paymentProvider']).to eq('stripe')
      expect(result_data['currency']).to eq('EUR')
      expect(result_data['timezone']).to be_nil
      expect(result_data['netPaymentTerm']).to eq(3)
      expect(result_data['invoiceGracePeriod']).to be_nil
      expect(result_data['providerCustomer']['id']).to be_present
      expect(result_data['providerCustomer']['providerCustomerId']).to eq('cu_12345')
      expect(result_data['providerCustomer']['providerPaymentMethods']).to eq(%w[card sepa_debit])
      expect(result_data['billingConfiguration']['documentLocale']).to eq('fr')
      expect(result_data['billingConfiguration']['id']).to eq("#{customer.id}-c0nf")
      expect(result_data['metadata'][0]['key']).to eq('test-key')
      expect(result_data['taxes'][0]['code']).to eq(tax.code)
    end
  end

  context 'with premium feature' do
    around { |test| lago_premium!(&test) }

    it 'updates a customer' do
      result = execute_graphql(
        current_user: membership.user,
        permissions: required_permissions,
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
end
