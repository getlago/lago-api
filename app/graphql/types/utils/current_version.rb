# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Utils
    class CurrentVersion < Types::BaseObject
      field :github_url, String, null: false
      field :number, String, null: false
    end
  end
end
