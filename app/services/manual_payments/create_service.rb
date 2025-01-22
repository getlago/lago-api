# frozen_string_literal: true

module ManualPayments
  class CreateService < BaseService
    def initialize(organization:, params:, skip_checks: false)
      @organization = organization
      @params = params
      @skip_checks = skip_checks

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
          created_at: parsed_paid_at
        )
        result.payment = payment

        total_paid_amount_cents = invoice.payments.where(payable_payment_status: :succeeded).sum(:amount_cents)

        params = {total_paid_amount_cents:}
        params[:payment_status] = 'succeeded' if total_paid_amount_cents == invoice.total_amount_cents
        Invoices::UpdateService.call!(invoice:, params:)

        Integrations::Aggregator::Payments::CreateJob.perform_later(payment:) if result.payment&.should_sync_payment?
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization, :params, :skip_checks

    def parsed_paid_at
      return nil if params[:paid_at].blank?

      Time.zone.parse(params[:paid_at])
    end

    def invoice
      @invoice ||= organization.invoices.find_by(id: params[:invoice_id])
    end

    def check_preconditions
	  return result.forbidden_failure! if !License.premium? && !skip_checks
      return result.not_found_failure!(resource: "invoice") unless invoice
      return result.forbidden_failure! unless invoice.organization.premium_integrations.include?('manual_payments')
      result.single_validation_failure!(error_code: "invalid_date", field: "paid_at") unless valid_paid_at?
    end

    def valid_paid_at?
      params[:paid_at].blank? || Utils::Datetime.valid_format?(params[:paid_at])
    end
  end
end
