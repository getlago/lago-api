# frozen_string_literal: true

module Emails
  class ResendService < BaseService
    Result = BaseResult

    # The parameters a refusal can name as its field on native v2, which puts the others on base.
    REQUEST_FIELDS = %i[to cc bcc].freeze

    def initialize(resource:, to: nil, cc: nil, bcc: nil)
      @resource = resource
      @to = to
      @cc = cc
      @bcc = bcc
      super
    end

    def call
      return result.not_found_failure!(resource: resource_type) unless resource
      return result.not_allowed_failure!(code: "payable_not_found") if missing_payable?
      return result.not_allowed_failure!(code: "#{resource_type}_not_finalized") unless valid_status?
      return result.forbidden_failure!(code: "premium_license_required") unless License.premium?

      refusals = validation_refusals
      return refuse(refusals) if refusals.any?

      send_email
      result
    end

    private

    attr_reader :resource, :to, :cc, :bcc

    def send_email
      mailer_class
        .with(mailer_params)
        .created
        .deliver_later
    end

    def mailer_class
      case resource
      when Invoice then InvoiceMailer
      when CreditNote then CreditNoteMailer
      when PaymentReceipt then PaymentReceiptMailer
      end
    end

    def mailer_params
      param_key = resource.class.name.underscore.to_sym
      {param_key => resource, :resend => true, :to => recipients_to, :cc => recipients_cc, :bcc => recipients_bcc}
    end

    # A payment receipt whose invoice or payment request no longer exists cannot be
    # rendered or emailed, so stop before the mailer generates any document.
    def missing_payable?
      resource.is_a?(PaymentReceipt) && resource.payment.payable.nil?
    end

    def valid_status?
      return true if resource.is_a?(PaymentReceipt)

      resource.finalized?
    end

    def billing_entity
      case resource
      when Invoice, PaymentReceipt
        resource.billing_entity
      when CreditNote
        resource.invoice.billing_entity
      end
    end

    def customer
      return resource.payment.payable.customer if resource.is_a?(PaymentReceipt)

      resource.customer
    end

    def resource_type
      resource&.class&.name&.underscore || "resource"
    end

    def recipients_to
      return Array(to) if to.present?

      [customer.email].compact
    end

    def recipients_cc
      Array(cc)
    end

    def recipients_bcc
      Array(bcc)
    end

    # {field => [code, message]}. v1 and GraphQL clients read the messages, sentences that quote the
    # addresses refused; native v2 renders the codes, which never echo the request.
    def validation_refusals
      refusals = {}
      refusals[:billing_entity] = ["billing_entity_email_not_configured", "must have email configured"] if billing_entity.email.blank?
      refusals[:from] = ["sender_email_not_configured", "must have a sender email address configured"] if billing_entity.from_email_address.blank?
      refusals[:invoice] = ["zero_amount_invoice", "must have a non-zero fees amount"] if zero_amount_invoice?
      refusals[:to] = ["value_is_mandatory", "must have at least one recipient"] if recipients_to.empty?

      {to: recipients_to, cc: recipients_cc, bcc: recipients_bcc}.each do |field, emails|
        invalid = emails.reject { |email| valid_email?(email) }
        refusals[field] = ["invalid_email_format", "invalid email format: #{invalid.join(", ")}"] if invalid.any?
      end

      refusals
    end

    def refuse(refusals)
      errors = refusals.transform_values { |(_code, message)| [message] }
      codes = refusals
        .group_by { |field, _| REQUEST_FIELDS.include?(field) ? field : :base }
        .transform_values { |entries| entries.map { |_field, (code, _message)| code } }

      result.validation_failure!(errors:, codes:)
    end

    def valid_email?(email)
      email.is_a?(String) && email.match?(Regex::EMAIL)
    end

    # Zero-amount invoices are intentionally never emailed (#1559), so InvoiceMailer
    # returns before building the message. Mirror its condition here, otherwise the
    # resend reports success while nothing is ever delivered. Note this is about the
    # fees amount, not the presence of fees: an invoice can carry fees that sum to zero.
    def zero_amount_invoice?
      resource.is_a?(Invoice) && resource.fees_amount_cents.zero?
    end
  end
end
