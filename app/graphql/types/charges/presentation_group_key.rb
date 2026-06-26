# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Charges
    class PresentationGroupKey < Types::BaseObject
      field :options, Types::Charges::PresentationGroupKeyOptions, null: true
      field :value, String, null: false
    end
  end
end
