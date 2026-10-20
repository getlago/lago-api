# frozen_string_literal: true

module X402
  class InvoicePaymentsController < ApplicationController
    include ApiErrors

    before_action { NullByteGuard.sanitize_params!(request, params) }

    REFUSALS = {
      "invalid_invoice_status_or_payment_status" => {status: 410, error: "Gone"},
      "invoice_payment_pending" => {status: 409, error: "Conflict"}
    }.freeze

    def create
      invoice = Invoice.find_by(x402_payment_token: params[:token])
      return not_found_error(resource: "invoice") unless invoice
      return forbidden_error(code: "feature_unavailable") unless invoice.organization.x402_payments_enabled?

      render_challenge(invoice)
    end

    private

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
      elsif result.error.is_a?(BaseService::ThirdPartyFailure)
        render(json: {status: 422, error: "Unprocessable Entity", code: "third_party_error"}, status: :unprocessable_content)
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
