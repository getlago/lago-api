# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module DataExports
    module CreditNotes
      class ExportTypeEnum < Types::BaseEnum
        graphql_name "CreditNoteExportTypeEnum"

        value "credit_notes"
        value "credit_note_items"
      end
    end
  end
end
