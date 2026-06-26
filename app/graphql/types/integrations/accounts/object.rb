# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Integrations
    module Accounts
      class Object < Types::BaseObject
        graphql_name "Account"

        field :external_account_code, String, null: false
        field :external_id, String, null: false
        field :external_name, String, null: true
      end
    end
  end
end
