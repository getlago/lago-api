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

        funding_instructions = fetch_funding_instructions
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
        unique_code = "funding_instructions_#{customer.id}"

        section_result = InvoiceCustomSections::CreateService.call(
          organization: customer.organization,
          create_params: {
            code: unique_code,
            name: "Funding Instructions",
            display_name: I18n.t("invoice.pay_with_bank_transfer", locale: preferred_locale),
            details: format_funding_details_text(funding_details_data)
          },
          selected: false,
          system_generated: true
        )

        return unless section_result.success?

        Customers::ManageInvoiceCustomSectionsService.call(
          customer: customer,
          skip_invoice_custom_sections: false,
          section_ids: [section_result.invoice_custom_section.id]
        )
      end

      def fetch_funding_instructions
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
        I18n.with_locale(preferred_locale) do
          lines = []
          t = ->(key) { I18n.t("invoice.#{key}") }

          lines << t.call(:bank_transfer_info)
          lines << ""

          type = funding_data[:type]
          addresses = funding_data[:financial_addresses] || []

          case type
          when "us_bank_transfer"
            addresses.each do |address|
              address_type = address[:type]&.to_sym
              details = address[address_type] || {}

              case address_type
              when :aba
                lines << "#{t.call(:bank_name)} #{details[:bank_name] || "-"}"
                lines << "#{t.call(:account_number)} #{details[:account_number] || "-"}"
                lines << "#{t.call(:routing_number)} #{details[:routing_number] || "-"}"
                lines << ""
              when :swift
                lines << "#{t.call(:bank_name)} #{details[:bank_name] || "-"}"
                lines << "#{t.call(:account_number)} #{details[:account_number] || "-"}"
                lines << "#{t.call(:swift_code)} #{details[:swift_code] || "-"}"
                lines << ""
              end
            end

          when "mx_bank_transfer"
            address = addresses.first
            details = address&.dig(:mx_bank_transfer) || {}
            lines << "#{t.call(:clabe)} #{details[:clabe] || "-"}"
            lines << "#{t.call(:bank_name)} #{details[:bank_name] || "-"}"
            lines << "#{t.call(:bank_code)} #{details[:bank_code] || "-"}"

          when "jp_bank_transfer"
            address = addresses.first
            details = address&.dig(:jp_bank_transfer) || {}
            lines << "#{t.call(:bank_code)} #{details[:bank_code] || "-"}"
            lines << "#{t.call(:bank_name)} #{details[:bank_name] || "-"}"
            lines << "#{t.call(:branch_code)} #{details[:branch_code] || "-"}"
            lines << "#{t.call(:branch_name)} #{details[:branch_name] || "-"}"
            lines << "#{t.call(:account_type)} #{details[:account_type] || "-"}"
            lines << "#{t.call(:account_number)} #{details[:account_number] || "-"}"
            lines << "#{t.call(:account_holder_name)} #{details[:account_holder_name] || "-"}"

          when "gb_bank_transfer"
            address = addresses.first
            details = address&.dig(:sort_code) || {}
            lines << "#{t.call(:account_number)} #{details[:account_number] || "-"}"
            lines << "#{t.call(:sort_code)} #{details[:sort_code] || "-"}"
            lines << "#{t.call(:account_holder_name)} #{details[:account_holder_name] || "-"}"

          when "eu_bank_transfer"
            address = addresses.first
            details = address&.dig(:iban) || {}
            lines << "#{t.call(:bic)} #{details[:bic] || "-"}"
            lines << "#{t.call(:iban)} #{details[:iban] || "-"}"
            lines << "#{t.call(:country)} #{details[:country] || "-"}"
            lines << "#{t.call(:account_holder_name)} #{details[:account_holder_name] || "-"}"

          else
            lines << "- #{t.call(:bank_transfer_info)} -"
          end

          lines.join("\n")
        end
      end

      def eligible_for_funding_instructions?
        stripe_customer.provider_customer_id.present? &&
          stripe_customer.provider_payment_methods&.include?("customer_balance") &&
          !customer.selected_invoice_custom_sections.exists?(code: "funding_instructions")
      end

      def customer_currency
        customer.currency.downcase
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
        customer_country = customer.country.upcase
        {type: "eu_bank_transfer", eu_bank_transfer: {country: customer_country}}
      end

      def stripe_api_key
        stripe_customer.payment_provider.secret_key
      end
    end
  end
end
