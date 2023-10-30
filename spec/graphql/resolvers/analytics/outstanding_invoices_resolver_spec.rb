# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::Analytics::OutstandingInvoicesResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($currency: CurrencyEnum) {
        outstandingInvoices(currency: $currency) {
          collection {
            month
            amountCents
            invoicesCount
            currency
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  context 'without premium feature' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
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

    it 'returns a list of outstanding invoices' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
      )

      outstanding_invoices_response = result['data']['outstandingInvoices']
      month = DateTime.parse outstanding_invoices_response['collection'].first['month']

      aggregate_failures do
        expect(month).to eq(DateTime.current.beginning_of_month)
        expect(outstanding_invoices_response['collection'].first['amountCents']).to eq('0')
        expect(outstanding_invoices_response['collection'].first['invoicesCount']).to eq('0')
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

    describe '#resolve' do
      subject(:resolve) { resolver.resolve }

      let(:resolver) { described_class.new(object: nil, context: nil, field: nil) }
      let(:current_organization) { create(:organization) }

      before do
        allow(Analytics::OutstandingInvoice).to receive(:find_all_by).and_return([])
        allow(resolver).to receive(:current_organization).and_return(current_organization)
        allow(resolver).to receive(:validate_organization!).and_return(true)

        resolve
      end

      it 'calls ::Analytics::OutstandingInvoice.find_all_by' do
        expect(Analytics::OutstandingInvoice).to have_received(:find_all_by).with(current_organization.id, months: 12)
      end
    end
  end
end
