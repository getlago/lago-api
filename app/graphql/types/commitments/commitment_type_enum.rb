# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Commitments
    class CommitmentTypeEnum < Types::BaseEnum
      Commitment::COMMITMENT_TYPES.keys.each do |type|
        value type
      end
    end
  end
end
