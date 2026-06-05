# frozen_string_literal: true

module Types
  module FinanceAssistant
    class Answer < Types::BaseObject
      graphql_name "FinanceAssistantAnswer"

      field :explanation, String, null: false
      field :results, String, null: false
      field :session_expired, Boolean, null: false
      field :session_id, ID, null: false
      field :sql_query, String, null: true
    end
  end
end
