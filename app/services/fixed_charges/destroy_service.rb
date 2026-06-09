# frozen_string_literal: true

module FixedCharges
  class DestroyService < BaseService
    Result = BaseResult[:fixed_charge]

    def initialize(fixed_charge:, cascade_updates: false, emit_plan_updated_details_webhook: false)
      @fixed_charge = fixed_charge
      @cascade_updates = cascade_updates
      @emit_plan_updated_details_webhook = emit_plan_updated_details_webhook

      super
    end

    def call
      return result.not_found_failure!(resource: "fixed_charge") unless fixed_charge

      previous_webhook_payload = plan_updated_details_payload

      fixed_charge.discard!
      result.fixed_charge = fixed_charge

      if cascade_updates && fixed_charge.children.exists?
        FixedCharges::DestroyChildrenJob.perform_later(fixed_charge.id)
      end

      send_updated_details_webhook(previous_webhook_payload)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    rescue Discard::RecordNotDiscarded => e
      result.service_failure!(code: "fixed_charge_already_deleted", message: e.message)
    end

    private

    attr_reader :fixed_charge, :cascade_updates, :emit_plan_updated_details_webhook

    delegate :plan, to: :fixed_charge

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
