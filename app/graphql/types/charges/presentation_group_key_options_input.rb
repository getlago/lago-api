# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Charges
    class PresentationGroupKeyOptionsInput < Types::BaseInputObject
      argument :display_in_invoice, Boolean, required: false
    end
  end
end
