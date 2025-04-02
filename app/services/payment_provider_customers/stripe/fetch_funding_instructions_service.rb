# frozen_string_literal: true

module PaymentProviderCustomers
  module Stripe
    class FetchFundingInstructionsService < BaseService
      # AssignFundingInstructionsSectionService
      Result = BaseResult[:funding_instructions]

      def initialize(stripe_customer)
        @stripe_customer = stripe_customer
        super
      end

      def call
        return result unless eligible_for_funding_instructions?

        funding_instructions = fetch_funding_instructions_from_stripe
        create_invoice_section_with_funding_info(funding_instructions)
        result.funding_instructions = funding_instructions
        result
      rescue ::Stripe::StripeError => e
        result.service_failure!(code: "stripe_error", message: e.message)
      end

      private

      attr_reader :stripe_customer
      delegate :customer, to: :stripe_customer

      def create_invoice_section_with_funding_info(funding_instructions)
        funding_details_data = funding_instructions.bank_transfer.to_hash

        section_result = InvoiceCustomSections::CreateService.call(
          organization: customer.organization,
          create_params: {
            code: "funding_instructions",
            name: "Funding Instructions",
            display_name: I18n.t("invoice.pay_with_bank_transfer", locale: preferred_locale),
            details: format_funding_details_text(funding_details_data)
          },
          selected: false
        )

        return unless section_result.success?

        Customers::ManageInvoiceCustomSectionsService.call(
          customer: customer,
          skip_invoice_custom_sections: false,
          section_ids: [section_result.invoice_custom_section.id]
        )
      end

      def fetch_funding_instructions_from_stripe
        ::Stripe::Customer.create_funding_instructions(
          stripe_customer.provider_customer_id,
          {
            funding_type: "bank_transfer",
            bank_transfer: funding_type_payload,
            currency: customer_currency
          },
          {api_key: stripe_api_key}
        )
      end

      def format_funding_details_text(funding_data)
        Rails.logger.debug funding_data
        Rails.logger.debug "formatar e meter detalhes no formato correcto"
      end

      def eligible_for_funding_instructions?
        stripe_customer.provider_customer_id.present? &&
          stripe_customer.provider_payment_methods&.include?("customer_balance") &&
          !customer.selected_invoice_custom_sections.exists?(code: "funding_instructions")
      end

      def customer_currency
        customer.organization.default_currency.downcase
      end

      def preferred_locale
        customer.preferred_document_locale
      end

      def funding_type_payload
        return eu_bank_transfer_payload if customer_currency == "eur"

        {
          "usd" => {type: "us_bank_transfer"},
          "gbp" => {type: "gb_bank_transfer"},
          "jpy" => {type: "jp_bank_transfer"},
          "mxn" => {type: "mx_bank_transfer"}
        }[customer_currency]
      end

      def eu_bank_transfer_payload
        customer_country = payment.customer.country.upcase
        {type: "eu_bank_transfer", eu_bank_transfer: {country: customer_country}}
      end

      def stripe_api_key
        stripe_customer.payment_provider.secret_key
      end
    end
  end
end
