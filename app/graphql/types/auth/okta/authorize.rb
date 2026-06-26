# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Auth
    module Okta
      class Authorize < Types::BaseObject
        field :url, String, null: false
      end
    end
  end
end
