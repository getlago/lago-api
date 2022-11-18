# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::CreditNoteResolver, type: :graphql do
  let(:query) do
    <<-GQL
      query($creditNoteId: ID!) {
        creditNote(id: $creditNoteId) {
          id
          number
          creditStatus
          reason
          totalAmountCents
          totalAmountCurrency
          creditAmountCents
          creditAmountCurrency
          balanceAmountCents
          balanceAmountCurrency
          totalAmountCents
          totalAmountCurrency
          vatAmountCents
          vatAmountCurrency
          subTotalVatExcludedAmountCents
          subTotalVatExcludedAmountCurrency
          createdAt
          updatedAt
          voidedAt
          refundedAt
          fileUrl
          invoice { id number }
          items {
            id
            amountCents
            amountCurrency
            createdAt
            fee { id amountCents itemType itemCode itemName }
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }

  let(:customer) { create(:customer, organization: membership.organization) }
  let(:credit_note) { create(:credit_note, customer: customer) }

  it 'returns a single credit note' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: customer.organization,
      query: query,
      variables: {
        creditNoteId: credit_note.id,
      },
    )

    credit_note_response = result['data']['creditNote']

    aggregate_failures do
      expect(credit_note_response['id']).to eq(credit_note.id)
    end
  end
end
