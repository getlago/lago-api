# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::Analytics::GrossRevenuesResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        grossRevenues {
          collection {
            month
            amountCents
            currency
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  # before { add_on }

  it 'returns a list of gross revenues' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
    )

    gross_revenues_response = result['data']['grossRevenues']
    month = DateTime.parse gross_revenues_response['collection'].first['month']

    aggregate_failures do
      expect(month).to eq(DateTime.current.beginning_of_month)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(current_user: membership.user, query:)

      expect_graphql_error(
        result:,
        message: 'Missing organization id',
      )
    end
  end

  context 'when not member of the organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query:,
      )

      expect_graphql_error(
        result:,
        message: 'Not in organization',
      )
    end
  end
end
