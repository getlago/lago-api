# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module OrderForms
    class VoidInput < Types::BaseInputObject
      description "Void Order Form input arguments"

      argument :id, ID, required: true
    end
  end
end
