# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Integrations
    class SyncCreditNoteInput < Types::BaseInputObject
      graphql_name "SyncIntegrationCreditNoteInput"

      argument :credit_note_id, ID, required: true
    end
  end
end
