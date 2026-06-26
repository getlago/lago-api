# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module UsageMonitoring
    module Alerts
      class ThresholdInput < BaseInputObject
        argument :code, String, required: false
        argument :recurring, Boolean, required: false
        argument :value, String, required: true
      end
    end
  end
end
