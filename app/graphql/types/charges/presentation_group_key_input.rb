# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Charges
    class PresentationGroupKeyInput < Types::BaseInputObject
      argument :options, Types::Charges::PresentationGroupKeyOptionsInput, required: false
      argument :value, String, required: true
    end
  end
end
