# frozen_string_literal: true

module Mutations
  module CreditNotes
    class Download < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'DownloadCreditNote'
      description 'Download a Credit Note PDF'

      argument :id, ID, required: true

      type Types::CreditNotes::Object

      def resolve(**args)
        validate_organization!

        # TODO: Security issue here, we can download a credit note from another organization.
        result = ::CreditNotes::GenerateService.new.call(credit_note_id: args[:id])

        result.success? ? result.credit_note : result_error(result)
      end
    end
  end
end
