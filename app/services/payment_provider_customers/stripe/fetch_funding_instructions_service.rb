# frozen_string_literal: true

module PaymentProviderCustomers
  module Stripe
    class FetchFundingInstructionsService < BaseService
      Result = BaseResult[:funding_instructions]

      def initialize(stripe_customer)
        @stripe_customer = stripe_customer
        super()
      end

      def call
        return result unless eligible?

        funding_instructions = fetch_from_stripe
        create_invoice_custom_section(funding_instructions)
        result.funding_instructions = funding_instructions
        result
      rescue ::Stripe::StripeError => e
        result.service_failure!(code: "stripe_error", message: e.message)
      end

      private

      attr_reader :stripe_customer
      delegate :customer, to: :stripe_customer

      def create_invoice_custom_section(funding_instructions)
        funding_data = funding_instructions.bank_transfer.to_hash

        create_result = InvoiceCustomSections::CreateService.call(
          organization: customer.organization,
          create_params: {
            code: "funding_instructions",
            name: "Funding Instructions",
            display_name: I18n.t("funding_instructions.display_name", locale: locale),
            details: build_details_text(funding_data)
          },
          selected: false # selection handled below
        )

        return unless create_result.success?

        Customers::ManageInvoiceCustomSectionsService.call(
          customer: customer,
          skip_invoice_custom_sections: false,
          section_ids: [create_result.id]
        )
      end

      def fetch_from_stripe
        ::Stripe::Customer.create_funding_instructions(
          stripe_customer.provider_customer_id,
          {
            funding_type: "bank_transfer",
            bank_transfer: bank_transfer_params,
            currency: currency
          },
          {api_key:}
        )
      end

      def build_details_text(funding_data)
        I18n.with_locale(locale) do
          lines = []
          t = ->(key) { I18n.t("funding_instructions.#{key}") }

          lines << t.call(:pay_with_bank_transfer)
          lines << ""
          lines << t.call(:bank_transfer_info)
          lines << ""

          type = funding_data[:type]
          address = funding_data[:financial_addresses]&.first
          details = address&.dig(type.to_sym) || {}

          case type
          when "us_bank_transfer"
            lines << "#{t.call(:bank_name)} #{details[:bank_name] || "-"}"
            lines << "#{t.call(:routing_number)} #{details[:routing_number] || "-"}"
            lines << "#{t.call(:account_number)} #{details[:account_number] || "-"}"
            lines << "#{t.call(:swift_code)} #{details[:swift_code] || "-"}"
            lines << "#{t.call(:account_holder_name)} #{details[:account_holder_name] || "-"}"

          when "eu_bank_transfer"
            lines << "#{t.call(:bic)} #{details[:bic] || "-"}"
            lines << "#{t.call(:iban)} #{details[:iban] || "-"}"
            lines << "#{t.call(:country)} #{funding_data[:country] || "-"}"
            lines << "#{t.call(:account_holder_name)} #{details[:account_holder_name] || "-"}"

          when "gb_bank_transfer"
            lines << "#{t.call(:sort_code)} #{details[:sort_code] || "-"}"
            lines << "#{t.call(:account_number)} #{details[:account_number] || "-"}"
            lines << "#{t.call(:account_holder_name)} #{details[:account_holder_name] || "-"}"

          when "jp_bank_transfer"
            lines << "#{t.call(:bank_name)} #{details[:bank_name] || "-"}"
            lines << "#{t.call(:branch_name)} #{details[:branch_name] || "-"}"
            lines << "#{t.call(:account_type)} #{details[:account_type] || "-"}"
            lines << "#{t.call(:account_number)} #{details[:account_number] || "-"}"
            lines << "#{t.call(:account_holder_name)} #{details[:account_holder_name] || "-"}"

          when "mx_bank_transfer"
            lines << "#{t.call(:clabe)} #{details[:clabe] || "-"}"
            lines << "#{t.call(:bank_name)} #{details[:bank_name] || "-"}"
            lines << "#{t.call(:account_holder_name)} #{details[:account_holder_name] || "-"}"

          else
            lines << "- #{I18n.t("funding_instructions.bank_transfer_info")} -"
          end

          lines.join("\n")
        end
      end

      def eligible?
        stripe_customer.provider_customer_id.present? &&
          stripe_customer.provider_payment_methods&.include?("customer_balance") &&
          !customer.selected_invoice_custom_sections.exists?(code: "funding_instructions")
      end

      def currency
        customer.organization.default_currency.downcase
      end

      def locale
        customer.preferred_document_locale
      end

      def bank_transfer_params
        return eu_bank_transfer_payload if currency == "eur"

        {
          "usd" => {type: "us_bank_transfer"},
          "gbp" => {type: "gb_bank_transfer"},
          "jpy" => {type: "jp_bank_transfer"},
          "mxn" => {type: "mx_bank_transfer"}
        }[currency]
      end

      def eu_bank_transfer_payload
        customer_country = payment.customer.country.upcase
        {type: "eu_bank_transfer", eu_bank_transfer: {country: customer_country}}
      end

      def api_key
        stripe_customer.payment_provider.secret_key
      end
    end
  end
end
