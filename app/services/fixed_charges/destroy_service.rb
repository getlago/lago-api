# frozen_string_literal: true

module FixedCharges
  class DestroyService < BaseService
    Result = BaseResult[:fixed_charge]

    def initialize(fixed_charge:, cascade_updates: false, send_webhook: true)
      @fixed_charge = fixed_charge
      @cascade_updates = cascade_updates
      @send_webhook = send_webhook

      super
    end

    def call
      return result.not_found_failure!(resource: "fixed_charge") unless fixed_charge

      fixed_charge.discard!
      result.fixed_charge = fixed_charge

      if cascade_updates && fixed_charge.children.exists?
        FixedCharges::DestroyChildrenJob.perform_later(fixed_charge.id)
      end

      SendWebhookJob.perform_after_commit("fixed_charge.deleted", result.fixed_charge) if send_webhook && result.success?

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    rescue Discard::RecordNotDiscarded => e
      result.service_failure!(code: "fixed_charge_already_deleted", message: e.message)
    end

    private

    attr_reader :fixed_charge, :cascade_updates, :send_webhook
  end
end
