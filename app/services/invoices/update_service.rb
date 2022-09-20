# frozen_string_literal: true

module Invoices
  class UpdateService < BaseService
    def update_from_api(invoice_id:, params:)
      invoice = Invoice.find_by(id: invoice_id)

      return result.not_found_failure!(resource: 'invoice') if invoice.blank?

      unless valid_status?(params[:status])
        return result.single_validation_failure!(
          field: :status,
          error_code: 'value_is_invalid',
        )
      end

      invoice.status = params[:status] if params.key?(:status)
      invoice.save!

      handle_prepaid_credits(invoice, params[:status])

      result.invoice = invoice
      track_payment_status_changed(invoice)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def valid_status?(status)
      Invoice::STATUS.include?(status&.to_sym)
    end

    def track_payment_status_changed(invoice)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'payment_status_changed',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          payment_status: invoice.status,
        },
      )
    end

    def handle_prepaid_credits(invoice, status)
      return unless invoice.invoice_type == 'credit'
      return unless status == 'succeeded'

      Invoices::PrepaidCreditJob.perform_later(invoice)
    end
  end
end
