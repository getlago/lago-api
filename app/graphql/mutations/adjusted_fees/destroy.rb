# frozen_string_literal: true

module Mutations
  module AdjustedFees
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "invoices:update"

      graphql_name "DestroyAdjustedFee"
      description "Deletes an adjusted fee"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        organization_draft_invoices = current_organization.invoices.draft.pluck(:id)
        fee = Fee.where(invoice_id: organization_draft_invoices).find_by(id:)

        result = ::AdjustedFees::DestroyService.call(fee:)

        result.success? ? result.fee : result_error(result)
      end
    end
  end
end
