# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CreditNotes::Void, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:credit_note) { create(:credit_note, customer:, invoice:) }

  let(:mutation) do
    <<~GQL
      mutation($input: VoidCreditNoteInput!) {
        voidCreditNote(input: $input) {
          id
          creditStatus
          canBeVoided
        }
      }
    GQL
  end

  it "voids the credit note" do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: credit_note.id
        }
      }
    )

    result_data = result["data"]["voidCreditNote"]

    aggregate_failures do
      expect(result_data["id"]).to eq(credit_note.id)
      expect(result_data["creditStatus"]).to eq("voided")
    end
  end

  context "when credit note is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            id: "foo_bar"
          }
        }
      )

      expect_not_found(result)
    end
  end

  context "without current user" do
    it "returns an error" do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: credit_note.id
          }
        }
      )

      expect_unauthorized_error(result)
    end
  end
end
