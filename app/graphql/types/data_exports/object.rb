# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module DataExports
    class Object < Types::BaseObject
      graphql_name "DataExport"

      field :id, ID, null: false
      field :status, Types::DataExports::StatusEnum, null: false
    end
  end
end
