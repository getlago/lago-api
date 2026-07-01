# frozen_string_literal: true

module Types
  module FinanceAssistant
    class Export < Types::BaseObject
      graphql_name "FinanceAssistantExport"

      field :content, String, null: false
      field :filename, String, null: false
      field :row_count, Integer, null: false
      field :truncated, Boolean, null: false
    end
  end
end
