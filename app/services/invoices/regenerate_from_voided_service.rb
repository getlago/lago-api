# frozen_string_literal: true

module Invoices
  class RegenerateFromVoidedService < BaseService
    def initialize(voided_invoice:, fees:)
      @voided_invoice = voided_invoice
      @fees = fees
      super
    end

    activity_loggable(
      action: "invoice.regenerated_from_voided",
      record: -> { voided_invoice }
    )

    def call
      return result.not_found_failure!(resource: "invoice") unless voided_invoice
      return result.not_allowed_failure!(code: "not_voided") unless voided_invoice.voided?

      # 1. Grace Period (draft status) - Done
      # 2. Usar a mesma data da voided invoice (bounderies) - Done
      # 3. Check Invoices::TransitionToFinalStatusService.call(invoice:) (finalized or draft status) - Done
      # 4. Mudar Mutation para usar um novo FeeInput criado exclusivamente para o regenerate_from_voided
      # 5. Adicionar charge_id e invoice_display_name - Done
      # 6. Verificar o funcionando do filter

      existing_fees = voided_invoice.fees.where(id: fees.map { |fee| fee[:id] })
      new_fees = fees.select { |fee| fee[:id].blank? }

      ActiveRecord::Base.transaction do
        generating_result = Invoices::CreateGeneratingService.call(
          customer: voided_invoice.customer,
          invoice_type: voided_invoice.invoice_type,
          currency: voided_invoice.currency,
          datetime: voided_invoice.created_at,
          voided_invoice_id: voided_invoice.id
        ) do |invoice|
          existing_fees.each do |fee_record|
            fee_record.dup.tap do |fee|
              fee.invoice = invoice
              fee.payment_status = :pending
              fee.taxes_amount_cents = 0
              fee.taxes_precise_amount_cents = 0.to_d

              fee_input = fees.find { |f| f[:id] == fee_record.id }
              if fee_input
                allowed_attrs = %i[charge_id subscription_id invoice_display_name units description amount_cents unit_amount_cents add_on_id]
                allowed_attrs.each do |attr|
                  fee[attr] = fee_input[attr] if fee_input.key?(attr)
                end
              end

              fee.save!

              taxes_result = Fees::ApplyTaxesService.call(fee: fee)
              taxes_result.raise_if_error!
            end
          end

          new_fees.each do |fee_attributes|
            new_fee = Fee.create!(fee_attributes.merge(invoice: invoice))

            taxes_result = Fees::ApplyTaxesService.call(fee: new_fee)
            taxes_result.raise_if_error!

            new_fee.save!
          end

          amounts_from_fees_result = Invoices::ComputeAmountsFromFees.call(invoice: invoice)
          amounts_from_fees_result.raise_if_error!

          if voided_invoice.customer.applicable_invoice_grace_period.positive?
            invoice.draft!
          else
            Invoices::TransitionToFinalStatusService.call(invoice: invoice)
          end
        end

        generating_result.raise_if_error!

        result.invoice = generating_result.invoice
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :voided_invoice, :fees
  end
end
