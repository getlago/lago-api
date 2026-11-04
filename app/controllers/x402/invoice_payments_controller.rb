# frozen_string_literal: true

module X402
  class InvoicePaymentsController < ApplicationController
    include Api::V1Errors

    before_action { NullByteGuard.sanitize_params!(request, params) }
    before_action :find_invoice
    before_action :ensure_x402_payments_enabled

    def show
      render_challenge(invoice)
    end

    def create
      render_challenge(invoice)
    end

    private

    attr_reader :invoice

    def find_invoice
      @invoice = Invoice.find_by!(x402_payment_token: params[:token])
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "invoice")
    end

    def ensure_x402_payments_enabled
      forbidden_error(code: "feature_unavailable") unless invoice.organization.x402_payments_enabled?
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
  end
end
