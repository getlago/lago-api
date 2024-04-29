# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::CustomerCreditNotesResolver, type: :graphql do
  let(:required_permission) { 'customers:view' }
  let(:query) do
    <<~GQL
      query($customerId: ID!) {
        customerCreditNotes(customerId: $customerId, limit: 5) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:credit_note) { create(:credit_note, organization:, customer:) }

  before do
    subscription
    credit_note
    create(:credit_note, :draft, organization:, customer:)
  end

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'customers:view'

  it 'returns a list of finalized credit_notes for a customer' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {
        customerId: customer.id,
      },
    )

    credit_notes_response = result['data']['customerCreditNotes']

    aggregate_failures do
      expect(credit_notes_response['collection'].count).to eq(1)
      expect(credit_notes_response['collection'].first['id']).to eq(credit_note.id)

      expect(credit_notes_response['metadata']['currentPage']).to eq(1)
      expect(credit_notes_response['metadata']['totalCount']).to eq(1)
    end
  end

  context 'when customer does not exists' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {
          customerId: '123456',
        },
      )

      expect_graphql_error(result:, message: 'Resource not found')
    end
  end
end
