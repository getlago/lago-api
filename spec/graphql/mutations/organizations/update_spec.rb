# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Organizations::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:mutation) do
    <<~GQL
      mutation($input: UpdateOrganizationInput!) {
        updateOrganization(input: $input) {
          webhookUrl
          legalNumber
          legalName
          email
          addressLine1
          addressLine2
          state
          zipcode
          city
          country
          timezone
          billingConfiguration { vatRate, invoiceFooter, invoiceGracePeriod, documentLocale }
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
          legalNumber: '1234',
          legalName: 'Foobar',
          email: 'foo@bar.com',
          addressLine1: 'Line 1',
          addressLine2: 'Line 2',
          state: 'Foobar',
          zipcode: 'FOO1234',
          city: 'Foobar',
          country: 'FR',
          billingConfiguration: {
            vatRate: 12.5,
            invoiceFooter: 'invoice footer',
            documentLocale: 'fr',
          },
        },
      },
    )

    result_data = result['data']['updateOrganization']

    aggregate_failures do
      expect(result_data['webhookUrl']).to eq('http://foo.bar')
      expect(result_data['legalNumber']).to eq('1234')
      expect(result_data['legalName']).to eq('Foobar')
      expect(result_data['email']).to eq('foo@bar.com')
      expect(result_data['addressLine1']).to eq('Line 1')
      expect(result_data['addressLine2']).to eq('Line 2')
      expect(result_data['state']).to eq('Foobar')
      expect(result_data['zipcode']).to eq('FOO1234')
      expect(result_data['city']).to eq('Foobar')
      expect(result_data['country']).to eq('FR')
      expect(result_data['billingConfiguration']['invoiceFooter']).to eq('invoice footer')
      expect(result_data['billingConfiguration']['invoiceGracePeriod']).to eq(0)
      expect(result_data['billingConfiguration']['vatRate']).to eq(12.5)
      expect(result_data['billingConfiguration']['documentLocale']).to eq('fr')
      expect(result_data['timezone']).to eq('TZ_UTC')
    end
  end

  context 'with premium features' do
    around { |test| lago_premium!(&test) }

    let(:timezone) { 'TZ_EUROPE_PARIS' }

    it 'updates an organization' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            email: 'foo@bar.com',
            timezone:,
            billingConfiguration: {
              invoiceGracePeriod: 3,
            },
          },
        },
      )

      result_data = result['data']['updateOrganization']

      aggregate_failures do
        expect(result_data['timezone']).to eq(timezone)
        expect(result_data['billingConfiguration']['invoiceGracePeriod']).to eq(3)
      end
    end

    context 'with Etc/GMT+12 timezone' do
      let(:timezone) { 'TZ_ETC_GMT_12' }

      it 'updates an organization' do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: membership.organization,
          query: mutation,
          variables: {
            input: {
              email: 'foo@bar.com',
              timezone:,
              billingConfiguration: {
                invoiceGracePeriod: 3,
              },
            },
          },
        )

        result_data = result['data']['updateOrganization']

        aggregate_failures do
          expect(result_data['timezone']).to eq(timezone)
          expect(result_data['billingConfiguration']['invoiceGracePeriod']).to eq(3)
        end
      end
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

      expect_graphql_error(result:, message: :unprocessable_entity)
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
