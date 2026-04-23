# frozen_string_literal: true

module PricingImports
  class ExecuteJob < ApplicationJob
    queue_as "long_running"

    def perform(pricing_import_id)
      pricing_import = PricingImport.find(pricing_import_id)
      PricingImports::ExecuteService.call!(pricing_import: pricing_import)
    end
  end
end
