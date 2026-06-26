# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Integrations
    class Salesforce < Types::BaseObject
      graphql_name "SalesforceIntegration"

      field :code, String, null: false
      field :id, ID, null: false
      field :instance_id, String, null: false
      field :name, String, null: false
    end
  end
end
