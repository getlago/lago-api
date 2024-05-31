# frozen_string_literal: true

module Mutations
  module CreditNotes
    class Download < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'credit_notes:view'

      graphql_name 'DownloadCreditNote'
      description 'Download a Credit Note PDF'

      argument :id, ID, required: true

      type Types::CreditNotes::Object

      def resolve(**args)
        result = ::CreditNotes::GenerateService.new(
          credit_note: context[:current_user].credit_notes.find_by(id: args[:id])
        ).call

        result.success? ? result.credit_note : result_error(result)
      end
    end
  end
end
