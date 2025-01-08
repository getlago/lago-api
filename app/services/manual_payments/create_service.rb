# frozen_string_literal: true

module ManualPayments
  class CreateService < BaseService
    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super
    end

    def call
      check_preconditions
      return result if result.error

      amount_cents = params[:amount_cents]

      ActiveRecord::Base.transaction do
        payment = invoice.payments.create!(
          amount_cents:,
          reference: params[:reference],
          amount_currency: invoice.currency,
          status: 'succeeded',
          payable_payment_status: 'succeeded',
          payment_type: :manual,
          created_at: params[:paid_at].present? ? Time.iso8601(params[:paid_at]) : nil
        )

        invoice.update!(total_paid_amount_cents: invoice.total_paid_amount_cents + amount_cents)

        result.payment = payment

        if invoice.payments.where(payable_payment_status: 'succeeded').sum(:amount_cents) == invoice.total_amount_cents
          payment.payable.update!(payment_status: 'succeeded')
        end

        Integrations::Aggregator::Payments::CreateJob.perform_later(payment:) if result.payment&.should_sync_payment?
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :params

    def invoice
      @invoice ||= organization.invoices.find_by(id: params[:invoice_id])
    end

    def check_preconditions
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "invoice") unless invoice
      result.forbidden_failure! unless invoice.organization.premium_integrations.include?('manual_payments')
    end
  end
end
