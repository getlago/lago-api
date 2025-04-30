# frozen_string_literal: true

module Types
  module UsageMonitoring
    module Alerts
      class ThresholdInput < BaseInputObject
        argument :code, String, required: true
        argument :value, String, required: true
      end
    end
  end
end
