# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::InvoiceCreditNotesResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($invoiceId: ID!) {
        invoiceCreditNotes(invoiceId: $invoiceId, limit: 5) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }
  let(:invoice) { create(:invoice, customer: customer) }
  let(:subscription) { create(:subscription, customer: customer, organization: organization) }
  let(:credit_note) { create(:credit_note, organization: organization, customer: customer, invoice: invoice) }

  before do
    subscription
    credit_note
  end

  it 'returns a list of credit_notes for an invoice' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
      variables: {
        invoiceId: invoice.id,
      },
    )

    credit_notes_response = result['data']['invoiceCreditNotes']

    aggregate_failures do
      expect(credit_notes_response['collection'].count).to eq(invoice.credit_notes.count)
      expect(credit_notes_response['collection'].first['id']).to eq(credit_note.id)

      expect(credit_notes_response['metadata']['currentPage']).to eq(1)
      expect(credit_notes_response['metadata']['totalCount']).to eq(1)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: query,
        variables: {
          invoiceId: invoice.id,
        },
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
        variables: {
          invoiceId: invoice.id,
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Not in organization',
      )
    end
  end

  context 'when invoice does not exists' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: query,
        variables: {
          invoiceId: '123456',
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Resource not found',
      )
    end
  end
end
