# frozen_string_literal: true

module Types
  module UsageMonitoring
    module Alerts
      class ThresholdInput < BaseInputObject
        argument :code, String, required: false
        argument :value, String, required: true
      end
    end
  end
end
