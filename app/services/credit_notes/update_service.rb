# frozen_string_literal: true

module CreditNotes
  class UpdateService < BaseService
    def initialize(credit_note:, **params)
      @credit_note = credit_note
      @params = params&.with_indifferent_access

      super
    end

    def call
      return result.not_found_failure!(resource: "credit_note") if credit_note.nil? || credit_note.draft?

      if params.key?(:refund_status)
        credit_note.refund_status = params[:refund_status]
        credit_note.refunded_at = Time.current if credit_note.succeeded?
      end
      credit_note.save!

      result.credit_note = credit_note

      Utils::SegmentTrack.refund_status_changed(credit_note.refund_status, credit_note.id, credit_note.organization.id)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :credit_note, :params
  end
end
