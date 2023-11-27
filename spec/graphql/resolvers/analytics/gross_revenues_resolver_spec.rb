# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::Analytics::GrossRevenuesResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($currency: CurrencyEnum, $externalCustomerId: String) {
        grossRevenues(currency: $currency, externalCustomerId: $externalCustomerId) {
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

  it 'returns a list of gross revenues' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
    )

    expect(result['data']['grossRevenues']['collection']).to eq([])
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

  describe '#resolve' do
    subject(:resolve) { resolver.resolve }

    let(:resolver) { described_class.new(object: nil, context: nil, field: nil) }
    let(:current_organization) { create(:organization) }

    before do
      allow(Analytics::GrossRevenue).to receive(:find_all_by).and_return([])
      allow(resolver).to receive(:current_organization).and_return(current_organization)
      allow(resolver).to receive(:validate_organization!).and_return(true)

      resolve
    end

    it 'calls ::Analytics::GrossRevenue.find_all_by' do
      expect(Analytics::GrossRevenue).to have_received(:find_all_by).with(current_organization.id, months: 12)
    end
  end
end
