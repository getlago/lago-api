# frozen_string_literal: true

module X402
  class InvoicePaymentsController < ApplicationController
    include Api::V1Errors

    before_action { NullByteGuard.sanitize_params!(request, params) }

    INVOICE_REFUSALS = %w[invoice_currency_not_supported wallet_not_x402_enabled].freeze

    def create
      invoice = Invoice.find_by(x402_payment_token: params[:token])
      return not_found_error(resource: "invoice") unless invoice
      return forbidden_error(code: "feature_unavailable") unless invoice.organization.x402_payments_enabled?

      header = request.headers[X402::Wire::V2Codec::PAYMENT_SIGNATURE]

      if header.blank?
        render_challenge(invoice)
      elsif request.post?
        render_payment(invoice, X402::Invoices::SettleService.call(invoice:, payment: X402::Wire::V2Codec.decode(header)))
      else
        response.headers["Allow"] = "POST"
        method_not_allowed_error(code: "payment_requires_post")
      end
    end

    private

    def render_payment(invoice, result)
      code = refusal_code(result.error)

      if result.success?
        render_receipt(result.settlement)
      elsif code && INVOICE_REFUSALS.exclude?(code)
        render_challenge(invoice, error: code)
      else
        render_error_response(result)
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
        render_error_response(challenge)
      end
    end

    def refusal_code(error)
      error.messages.values.flatten.first if error.is_a?(BaseService::ValidationFailure)
    end
  end
end
