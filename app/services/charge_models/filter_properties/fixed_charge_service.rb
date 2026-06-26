# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module ChargeModels
  module FilterProperties
    class FixedChargeService < BaseService
      # FixedCharge has no additional base attributes
      # and uses only the standard, graduated, and volume charge models
      # which are already handled in the base class
    end
  end
end
