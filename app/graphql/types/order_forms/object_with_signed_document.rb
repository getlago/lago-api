# frozen_string_literal: true

module Types
  module OrderForms
    class ObjectWithSignedDocument < Types::OrderForms::Object
      graphql_name "OrderFormWithSignedDocument"

      field :signed_document_url, String, null: true
    end
  end
end
