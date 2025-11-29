# frozen_string_literal: true

module CreditNotes
  class UpdateService < BaseService
    use Middlewares::Yabeda::CountErrorsMiddleware
    use Middlewares::Yabeda::DurationMiddleware

    def initialize(credit_note:, **params)
      @params = params&.with_indifferent_access
      @credit_note = credit_note
      @refund_status = @params[:refund_status]

      super
    end

    def call
      return result.not_found_failure!(resource: "credit_note") if credit_note.nil? || credit_note.draft?

      ActiveRecord::Base.transaction do
        if update_refund_status?
          credit_note.refund_status = refund_status
          credit_note.refunded_at = Time.current if credit_note.succeeded?
        end

        update_metadata!

        # Added for visibility of what's going on
        # (it is expected, though, that the `update_metadata!` to save the credit not by itself)
        credit_note.save! if credit_note.changed?
      end

      result.credit_note = credit_note

      Utils::SegmentTrack.refund_status_changed(credit_note.refund_status, credit_note.id, credit_note.organization.id)

      result
    rescue ArgumentError
      result.single_validation_failure!(field: :refund_status, error_code: "value_is_invalid")
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :credit_note, :params, :refund_status

    def update_refund_status?
      params.key?(:refund_status)
    end

    def update_metadata!
      value = params[:metadata]&.then { |m| m.respond_to?(:to_unsafe_h) ? m.to_unsafe_h : m.to_h }
      Metadata::UpdateItemService.call!(credit_note, value:, replace: !!params[:replace_metadata])
    end
  end
end
