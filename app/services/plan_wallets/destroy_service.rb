# frozen_string_literal: true

module PlanWallets
  # Removes a wallet template from a plan. Contracts hold their own copy, so theirs stay.
  class DestroyService < BaseService
    Result = BaseResult[:plan_wallet]

    activity_loggable(
      action: "plan_wallet.deleted",
      record: -> { plan_wallet }
    )

    def initialize(plan_wallet:)
      @plan_wallet = plan_wallet
      super
    end

    def call
      return result.not_found_failure!(resource: "wallet") unless plan_wallet

      plan_wallet.with_lock do
        return result.not_found_failure!(resource: "wallet") if plan_wallet.discarded?

        # The taxes, scope and metadata stay on the deleted template, which still renders them.
        plan_wallet.credit_allocations.update_all(deleted_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        plan_wallet.discard!
      end

      result.plan_wallet = plan_wallet
      result
    end

    private

    attr_reader :plan_wallet
  end
end
