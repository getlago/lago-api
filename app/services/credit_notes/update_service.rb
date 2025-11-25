# frozen_string_literal: true

module CreditNotes
  class UpdateService < BaseService
    def initialize(credit_note:, partial_metadata: false, **params)
      @params = params&.with_indifferent_access
      @credit_note = credit_note
      @refund_status = params[:refund_status]
      @partial_metadata = partial_metadata
      @metadata_value = params[:metadata]&.then { |m| m.respond_to?(:to_unsafe_h) ? m.to_unsafe_h : m.to_h }

      super
    end

    def call
      return result.not_found_failure!(resource: "credit_note") if credit_note.nil? || credit_note.draft?

      ActiveRecord::Base.transaction do
        if update_refund_status?
          credit_note.refund_status = refund_status
          credit_note.refunded_at = Time.current if credit_note.succeeded?
        end

        change_metadata!
        credit_note.save!
        delete_metadata!
      end

      result.credit_note = credit_note

      Utils::SegmentTrack.refund_status_changed(credit_note.refund_status, credit_note.id, credit_note.organization.id)

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :credit_note, :params, :refund_status, :metadata_value, :partial_metadata

    def update_refund_status?
      params.key?(:refund_status)
    end

    def create_metadata?
      credit_note.metadata.blank? && !metadata_value.nil? && (metadata_value.present? || !partial_metadata)
    end

    def replace_metadata?
      credit_note.metadata.present? && !partial_metadata && !metadata_value.nil?
    end

    def merge_metadata?
      credit_note.metadata.present? && partial_metadata && metadata_value.present?
    end

    def delete_metadata?
      return @delete_metadata if defined?(@delete_metadata)
      @delete_metadata = credit_note.metadata.present? && !partial_metadata && metadata_value.nil?
    end

    def change_metadata!
      if create_metadata?
        credit_note.create_metadata!(
          owner: credit_note,
          organization_id: credit_note.organization_id,
          value: metadata_value
        )
      elsif replace_metadata?
        credit_note.metadata.update!(value: metadata_value)
      elsif merge_metadata?
        credit_note.metadata.update!(value: credit_note.metadata.value.merge(metadata_value))
      end
    end

    def delete_metadata!
      credit_note.metadata.destroy! if delete_metadata?
    end
  end
end
