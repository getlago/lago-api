# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module BillingEntities
    class DocumentNumberingEnum < Types::BaseEnum
      graphql_name "BillingEntityDocumentNumberingEnum"
      description "Document numbering type"

      ::BillingEntity::DOCUMENT_NUMBERINGS.keys.each do |code|
        value code
      end
    end
  end
end
