# frozen_string_literal: true

module ProductFilters
  class DestroyService < BaseService
    Result = BaseResult[:product_filter]

    activity_loggable(
      action: "product_filter.deleted",
      record: -> { product_filter }
    )

    def initialize(product_filter:)
      @product_filter = product_filter
      super
    end

    def call
      return result.not_found_failure!(resource: "product_filter") unless product_filter

      # Same rule as product_categories and items: a catalog object cannot be deleted while
      # its item is attached to a plan or subscription. Detach first, then delete.
      if product_filter.attached_to_plan_or_subscription?
        return result.single_validation_failure!(field: :product_filter, error_code: "attached_to_plan_or_subscription")
      end

      ActiveRecord::Base.transaction do
        discard_contract_alerts

        # Rate cards scoped to this filter lose their scope when it is deleted, so
        # discard them too (all unattached, guaranteed by the guard above) — mirrors
        # the product destroy cascade and avoids orphaned rate cards.
        scoped_cards = product_filter.product.rate_cards.where(product_filter_id: product_filter.id)
        RateCardRate.where(rate_card_id: scoped_cards.ids).discard_all!
        scoped_cards.discard_all!

        product_filter.values.discard_all!
        product_filter.discard!
        SendWebhookJob.perform_after_commit("product_filter.deleted", product_filter)
      end

      result.product_filter = product_filter
      result
    end

    private

    attr_reader :product_filter

    def discard_contract_alerts
      # Alert rows first, in a stable order, or this deadlocks against evaluation and edits.
      alert_ids = product_filter.contract_alerts.order(:id).lock.pluck(:id)

      UsageMonitoring::ContractAlertThreshold.where(contract_alert_id: alert_ids).delete_all
      deleted_at = Time.current
      UsageMonitoring::ContractAlert.where(id: alert_ids).update_all(deleted_at:, updated_at: deleted_at) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
