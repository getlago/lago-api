# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::InvoicesResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        invoices(limit: 5) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer_first) { create(:customer, organization: organization) }
  let(:customer_second) { create(:customer, organization: organization) }
  let(:invoice_first) { create(:invoice, customer: customer_first, payment_status: :pending) }
  let(:invoice_second) { create(:invoice, customer: customer_second, payment_status: :succeeded) }

  before do
    invoice_first
    invoice_second
  end

  it 'returns all invoices' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
    )

    invoices_response = result['data']['invoices']
    returned_ids = invoices_response['collection'].map { |hash| hash['id'] }

    aggregate_failures do
      expect(invoices_response['collection'].count).to eq(2)
      expect(returned_ids).to include(invoice_first.id)
      expect(returned_ids).to include(invoice_second.id)

      expect(invoices_response['metadata']['currentPage']).to eq(1)
      expect(invoices_response['metadata']['totalCount']).to eq(2)
    end
  end

  context 'when filtering by succeeded payment status' do
    let(:query) do
      <<~GQL
      query {
        invoices(limit: 5, paymentStatus: [succeeded]) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
      GQL
    end

    it 'returns all succeeded invoices' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: query,
      )

      invoices_response = result['data']['invoices']
      returned_ids = invoices_response['collection'].map { |hash| hash['id'] }

      aggregate_failures do
        expect(invoices_response['collection'].count).to eq(1)
        expect(returned_ids).not_to include(invoice_first.id)
        expect(returned_ids).to include(invoice_second.id)

        expect(invoices_response['metadata']['currentPage']).to eq(1)
        expect(invoices_response['metadata']['totalCount']).to eq(1)
      end
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: query,
      )

      expect_graphql_error(
        result: result,
        message: 'Missing organization id',
      )
    end
  end

  context 'when not member of the organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query: query,
      )

      expect_graphql_error(
        result: result,
        message: 'Not in organization',
      )
    end
  end
end
