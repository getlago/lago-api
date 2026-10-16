# frozen_string_literal: true

module X402
  class InvoicePaymentsController < ApplicationController
    include ApiErrors

    REFUSALS = {
      "invalid_invoice_status_or_payment_status" => {status: 410, error: "Gone"},
      "invoice_payment_pending" => {status: 409, error: "Conflict"}
    }.freeze
    INVOICE_REFUSALS = %w[invoice_currency_not_supported wallet_not_x402_enabled].freeze

    def create
      invoice = Invoice.find_by(x402_payment_token: params[:token])
      return not_found_error(resource: "invoice") unless invoice
      return forbidden_error(code: "feature_unavailable") unless invoice.organization.x402_payments_enabled?

      header = request.headers[X402::Wire::V2Codec::PAYMENT_SIGNATURE]

      if header
        render_payment(invoice, X402::Invoices::SettleService.call(invoice:, payment: X402::Wire::V2Codec.decode(header)))
      else
        render_challenge(invoice)
      end
    end

    private

    def render_payment(invoice, result)
      code = refusal_code(result.error)

      if result.success? && result.settlement.settled?
        render_receipt(result.settlement)
      elsif result.success?
        render_refusal("invoice_payment_pending")
      elsif code && !REFUSALS.key?(code) && INVOICE_REFUSALS.exclude?(code)
        render_challenge(invoice, error: code)
      else
        render_failure(result)
      end
    end

    def render_receipt(settlement)
      settlement_response = X402::Wire::V2Codec.settlement_response(settlement)

      response.headers[X402::Wire::V2Codec::PAYMENT_RESPONSE] = X402::Wire::V2Codec.encode(settlement_response)
      render(json: settlement_response)
    end

    def render_challenge(invoice, error: nil)
      challenge = X402::Invoices::GenerateChallengeService.call(invoice:)

      if challenge.success?
        payment_required = X402::Wire::V2Codec.payment_required(
          requirements: challenge.requirements,
          resource: X402::Wire::V2Codec.invoice_resource(invoice),
          error:
        )
        response.headers[X402::Wire::V2Codec::PAYMENT_REQUIRED] = X402::Wire::V2Codec.encode(payment_required)
        render(json: payment_required, status: :payment_required)
      else
        render_failure(challenge)
      end
    end

    def render_failure(result)
      code = refusal_code(result.error)

      if REFUSALS.key?(code)
        render_refusal(code)
      else
        render_error_response(result)
      end
    end

    def render_refusal(code)
      refusal = REFUSALS.fetch(code)

      render(json: {**refusal, code:}, status: refusal[:status])
    end

    def refusal_code(error)
      error.messages.values.flatten.first if error.is_a?(BaseService::ValidationFailure)
    end
  end
end
