# frozen_string_literal: true

module Taxes
  class UpdateAllEuTaxesJob < ApplicationJob
    queue_as "default"

    def perform
      Organization.where(eu_tax_management: true).find_each do |org|
        ::Taxes::UpdateOrganizationEuTaxesJob.perform_later(org)
      end
    end
  end
end
