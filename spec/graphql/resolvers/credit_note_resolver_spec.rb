# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CreditNoteResolver, type: :graphql do
  let(:query) do
    <<-GQL
      query($creditNoteId: ID!) {
        creditNote(id: $creditNoteId) {
          id
          number
          creditStatus
          reason
          currency
          totalAmountCents
          creditAmountCents
          balanceAmountCents
          totalAmountCents
          taxesAmountCents
          subTotalExcludingTaxesAmountCents
          couponsAdjustmentAmountCents
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
          appliedTaxes {
            taxCode
            taxName
            taxRate
            taxDescription
            amountCents
            amountCurrency
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }

  let(:customer) { create(:customer, organization: membership.organization) }
  let(:invoice) { create(:invoice, organization: membership.organization, customer:) }
  let(:credit_note) { create(:credit_note, customer:, invoice:) }

  it "returns a single credit note" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: customer.organization,
      query:,
      variables: {
        creditNoteId: credit_note.id
      }
    )

    credit_note_response = result["data"]["creditNote"]

    aggregate_failures do
      expect(credit_note_response["id"]).to eq(credit_note.id)
    end
  end
end
