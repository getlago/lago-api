# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Organizations::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:mutation) do
    <<~GQL
      mutation($input: UpdateOrganizationInput!) {
        updateOrganization(input: $input) {
          webhookUrl
          vatRate
          legalNumber
          legalName
          email
          addressLine1
          addressLine2
          state
          zipcode
          city
          country
          invoiceFooter
          invoiceGracePeriod
          timezone
        }
      }
    GQL
  end

  it 'updates an organization' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          webhookUrl: 'http://foo.bar',
          vatRate: 12.5,
          legalNumber: '1234',
          legalName: 'Foobar',
          email: 'foo@bar.com',
          addressLine1: 'Line 1',
          addressLine2: 'Line 2',
          state: 'Foobar',
          zipcode: 'FOO1234',
          city: 'Foobar',
          country: 'FR',
          timezone: 'TZ_EUROPE_PARIS',
          invoiceFooter: 'invoice footer',
          invoiceGracePeriod: 3,
        },
      },
    )

    result_data = result['data']['updateOrganization']

    aggregate_failures do
      expect(result_data['webhookUrl']).to eq('http://foo.bar')
      expect(result_data['vatRate']).to eq(12.5)
      expect(result_data['legalNumber']).to eq('1234')
      expect(result_data['legalName']).to eq('Foobar')
      expect(result_data['email']).to eq('foo@bar.com')
      expect(result_data['addressLine1']).to eq('Line 1')
      expect(result_data['addressLine2']).to eq('Line 2')
      expect(result_data['state']).to eq('Foobar')
      expect(result_data['zipcode']).to eq('FOO1234')
      expect(result_data['city']).to eq('Foobar')
      expect(result_data['country']).to eq('FR')
      expect(result_data['invoiceFooter']).to eq('invoice footer')
      # TODO(:grace_period): Grace period update is turned off for now
      # expect(result_data['invoiceGracePeriod']).to eq(3)
      # TODO(:timezone): Timezone update is turned off for now
      # expect(result_data['timezone']).to eq('TZ_EUROPE_PARIS')
    end
  end

  context 'with invalid webhook url' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            webhookUrl: 'bad_url',
          },
        },
      )

      expect_graphql_error(result: result, message: :unprocessable_entity)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            webhookUrl: 'http://foo.bar',
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            webhookUrl: 'http://foo.bar',
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
