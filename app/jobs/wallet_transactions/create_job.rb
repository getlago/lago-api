# frozen_string_literal: true

module WalletTransactions
  class CreateJob < ApplicationJob
    queue_as "high_priority"

    def perform(organization_id:, params:, unique_transaction: false)
      # Apply uniqueness only when unique_transaction flag is true
      if unique_transaction
        lock_key = [
          organization_id,
          params[:wallet_id],
          params[:paid_credits],
          params[:granted_credits]
        ].join(':')

        # Try to acquire a lock, and return if we can't (meaning a duplicate job)
        unless ActiveJob::Uniqueness.lock!(
          lock_key: "threshold_wallet_transaction:#{lock_key}",
          strategy: :until_executed,
          on_conflict: :log
        )
          # Job is a duplicate, so we return early
          return
        end
      end

      # Continue with normal job execution
      organization = Organization.find(organization_id)
      WalletTransactions::CreateFromParamsService.call!(organization:, params:)
    end
  end
end
