# frozen_string_literal: true

class Invoices::UpdateService < BaseService
  def update_from_api(invoice_id:, params:)
    invoice = Invoice.find_by(id: invoice_id)

    return result.not_found_failure!(resource: 'invoice') if invoice.blank?
    return result.fail!(code: 'invalid_status') unless valid_status?(params[:status])

    invoice.status = params[:status] if params.key?(:status)
    invoice.save!

    handle_prepaid_credits(invoice, params[:status])

    result.invoice = invoice
    track_payment_status_changed(invoice)
    result
  rescue ActiveRecord::RecordInvalid => e
    result.fail_with_validations!(e.record)
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
