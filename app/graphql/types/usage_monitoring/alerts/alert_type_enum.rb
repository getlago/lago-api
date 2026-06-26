# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module UsageMonitoring
    module Alerts
      class AlertTypeEnum < Types::BaseEnum
        ::UsageMonitoring::Alert::STI_MAPPING.keys.each do |type|
          value type
        end
      end
    end
  end
end
