# frozen_string_literal: true

module WalletTransactions
  class CreateJob < ApplicationJob
    queue_as "high_priority"
    unique :until_executed, on_conflict: :log

    def perform(organization_id:, params:, unique_transaction: false)
      organization = Organization.find(organization_id)
      WalletTransactions::CreateFromParamsService.call!(organization:, params:)
    end

    # Override lock_key_arguments to conditionally include only relevant parameters
    # when uniqueness is needed (unique_transaction is true)
    def lock_key_arguments
      org_id = arguments.first[:organization_id]
      params = arguments.first[:params]
      unique_transaction = arguments.first[:unique_transaction] || false

      if unique_transaction
        [
          org_id,
          params[:wallet_id],
          params[:paid_credits],
          params[:granted_credits]
        ]
      else
        # Return a unique value for each job to effectively disable uniqueness
        # when unique_transaction is false
        [SecureRandom.uuid]
      end
    end
  end
end
