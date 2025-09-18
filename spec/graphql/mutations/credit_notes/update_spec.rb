# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::CreditNotes::Update do
  let(:required_permission) { "credit_notes:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:credit_note) { create(:credit_note, customer:, invoice:) }

  let(:mutation) do
    <<~GQL
      mutation($input: UpdateCreditNoteInput!) {
        updateCreditNote(input: $input) {
          id
          refundStatus
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires permission", "credit_notes:update"

  it "updates the credit note" do
    result = execute_graphql(
      current_user: membership.user,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: credit_note.id,
          refundStatus: "succeeded"
        }
      }
    )

    result_data = result["data"]["updateCreditNote"]

    aggregate_failures do
      expect(result_data["id"]).to eq(credit_note.id)
      expect(result_data["refundStatus"]).to eq("succeeded")
    end
  end

  context "when credit note is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            id: "foo_bar",
            refundStatus: "succeeded"
          }
        }
      )

      expect_not_found(result)
    end
  end
end
