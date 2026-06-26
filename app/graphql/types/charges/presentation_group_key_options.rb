# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Charges
    class PresentationGroupKeyOptions < Types::BaseObject
      field :display_in_invoice, Boolean, null: true
    end
  end
end
