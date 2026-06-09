# frozen_string_literal: true

module Charges
  class DestroyService < BaseService
    Result = BaseResult[:charge]

    def initialize(charge:, cascade_updates: false, emit_plan_updated_details_webhook: false)
      @charge = charge
      @cascade_updates = cascade_updates
      @emit_plan_updated_details_webhook = emit_plan_updated_details_webhook

      super
    end

    def call
      return result.not_found_failure!(resource: "charge") unless charge

      previous_webhook_payload = plan_updated_details_payload

      ActiveRecord::Base.transaction do
        charge.discard!

        deleted_at = Time.current
        # rubocop:disable Rails/SkipsModelValidations
        charge.filter_values.update_all(deleted_at:)
        charge.filters.update_all(deleted_at:)
        # rubocop:enable Rails/SkipsModelValidations

        result.charge = charge
      end

      if cascade_updates && charge.children.exists?
        Charges::DestroyChildrenJob.perform_later(charge.id)
      end

      send_updated_details_webhook(previous_webhook_payload)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :charge, :cascade_updates, :emit_plan_updated_details_webhook

    delegate :plan, to: :charge

    def plan_updated_details_payload
      if emit_plan_updated_details_webhook && plan.organization.webhook_endpoints.exists?
        Plans::WebhookPayload.snapshot(plan)
      end
    end

    def send_updated_details_webhook(previous_payload)
      if previous_payload
        SendWebhookJob.perform_after_commit(
          "plan.updated_details",
          plan,
          Plans::WebhookPayload.updated_details_options(previous: previous_payload, current_plan: plan)
        )
      end
    end
  end
end
