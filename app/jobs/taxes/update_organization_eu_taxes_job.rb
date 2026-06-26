# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Taxes
  class UpdateOrganizationEuTaxesJob < ApplicationJob
    queue_as "default"

    def perform(organization)
      Taxes::AutoGenerateService.call!(organization:)
    end
  end
end
