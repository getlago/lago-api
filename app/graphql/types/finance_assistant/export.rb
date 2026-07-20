# frozen_string_literal: true

module Types
  module FinanceAssistant
    class Export < Types::BaseObject
      graphql_name "FinanceAssistantExport"

      field :file_url, String, null: false
      field :filename, String, null: false
    end
  end
end
