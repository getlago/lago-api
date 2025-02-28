# frozen_string_literal: true

module WalletTransactions
  class CreateJob < ApplicationJob
    queue_as "high_priority"

    def perform(organization_id:, params:)
      organization = Organization.find(organization_id)
      WalletTransactions::CreateFromParamsService.call!(organization:, params:)
    end
  end
end
