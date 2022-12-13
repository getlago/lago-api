# frozen_string_literal: true

module Invoices
  class UpdateService < BaseService
    def initialize(invoice:, params:)
      @invoice = invoice
      @params = params

      super
    end

    def call
      return result.not_found_failure!(resource: 'invoice') if invoice.nil?

      unless valid_payment_status?(params[:payment_status])
        return result.single_validation_failure!(
          field: :payment_status,
          error_code: 'value_is_invalid',
        )
      end

      invoice.payment_status = params[:payment_status] if params.key?(:payment_status)
      invoice.save!

      handle_prepaid_credits(params[:payment_status])

      result.invoice = invoice
      track_payment_status_changed
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice, :params

    def valid_payment_status?(payment_status)
      Invoice::PAYMENT_STATUS.include?(payment_status&.to_sym)
    end

    def track_payment_status_changed
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'payment_status_changed',
        properties: {
          organization_id: invoice.organization.id,
          invoice_id: invoice.id,
          payment_status: invoice.payment_status,
        },
      )
    end

    def handle_prepaid_credits(payment_status)
      return unless invoice.invoice_type == 'credit'
      return unless payment_status == 'succeeded'

      Invoices::PrepaidCreditJob.perform_later(invoice)
    end
  end
end
