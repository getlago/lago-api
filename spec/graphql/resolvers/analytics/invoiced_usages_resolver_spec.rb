# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::Analytics::InvoicedUsagesResolver, type: :graphql do
  let(:required_permission) { 'analytics:view' }
  let(:query) do
    <<~GQL
      query($currency: CurrencyEnum) {
        invoicedUsages(currency: $currency) {
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

  it_behaves_like 'requires permission', 'analytics:view'

  context 'without premium feature' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
      )

      expect_graphql_error(
        result:,
        message: 'unauthorized',
      )
    end
  end

  context 'with premium feature' do
    around { |test| lago_premium!(&test) }

    it 'returns a list of invoiced usages' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
      )

      expect(result['data']['invoicedUsages']['collection']).to eq([])
    end

    context 'without current organization' do
      it 'returns an error' do
        result = execute_graphql(current_user: membership.user, permissions: required_permission, query:)

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
          permissions: Permission::EMPTY_PERMISSIONS_HASH,
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
        allow(Analytics::InvoicedUsage).to receive(:find_all_by).and_return([])
        allow(resolver).to receive(:current_organization).and_return(current_organization)
        allow(resolver).to receive(:validate_organization!).and_return(true)

        resolve
      end

      it 'calls ::Analytics::InvoicedUsage.find_all_by' do
        expect(Analytics::InvoicedUsage).to have_received(:find_all_by).with(current_organization.id, months: 12)
      end
    end
  end
end
