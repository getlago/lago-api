# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::CustomerPortal::GenerateUrl, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:user) { membership.user }
  let(:mutation) do
    <<-GQL
      mutation($input: GenerateCustomerPortalUrlInput!) {
        generateCustomerPortalUrl(input: $input) {
          url
        }
      }
    GQL
  end

  context 'when licence is premium' do
    around { |test| lago_premium!(&test) }

    it 'returns customer portal url' do
      result = execute_graphql(
        current_organization: organization,
        current_user: user,
        query: mutation,
        variables: {
          input: { id: customer.id },
        },
      )

      data = result['data']['generateCustomerPortalUrl']

      expect(data['url']).to include('/customer-portal/')
    end

    context 'without current user' do
      it 'returns an error' do
        result = execute_graphql(
          current_organization: organization,
          query: mutation,
          variables: {
            input: { id: customer.id },
          },
        )

        expect_unauthorized_error(result)
      end
    end

    context 'without current organization' do
      it 'returns an error' do
        result = execute_graphql(
          current_user: user,
          query: mutation,
          variables: {
            input: { id: customer.id },
          },
        )

        expect_forbidden_error(result)
      end
    end
  end
end
