# frozen_string_literal: true

module PlanWallets
  # Removes a wallet template from a plan. Contracts hold their own copy, so theirs stay.
  class DestroyService < BaseService
    Result = BaseResult[:plan_wallet]

    activity_loggable(
      action: "plan_wallet.deleted",
      record: -> { plan_wallet },
      condition: -> { emit_events }
    )

    def initialize(plan_wallet:, emit_events: true)
      @plan_wallet = plan_wallet
      @emit_events = emit_events
      super
    end

    def call
      return result.not_found_failure!(resource: "plan_wallet") unless plan_wallet

      plan_wallet.with_lock do
        return result.not_found_failure!(resource: "plan_wallet") if plan_wallet.discarded?

        # The taxes, scope and metadata stay on the deleted template, which still renders them.
        deleted_at = Time.current
        plan_wallet.credit_allocations.update_all(deleted_at:, updated_at: deleted_at) # rubocop:disable Rails/SkipsModelValidations
        UsageMonitoring::CatalogWalletAlerts::DeleteAllService.call!(plan_wallets: plan_wallet)
        plan_wallet.discard!
      end

      result.plan_wallet = plan_wallet
      result
    end

    private

    attr_reader :plan_wallet, :emit_events
  end
end
