# frozen_string_literal: true

module InvoiceCustomSections
  class FundingInstructionsFormatterService < BaseService
    def initialize(funding_data:, locale:)
      @funding_data = funding_data
      @locale = locale
      super
    end

    def call
      I18n.with_locale(locale) do
        lines = []
        t = ->(key) { I18n.t("invoice.#{key}") }

        lines << t.call(:bank_transfer_info)
        lines << ""

        case funding_data[:type]
        when "us_bank_transfer" then format_us_bank_transfer(lines, t)
        when "mx_bank_transfer" then format_mx_bank_transfer(lines, t)
        when "jp_bank_transfer" then format_jp_bank_transfer(lines, t)
        when "gb_bank_transfer" then format_gb_bank_transfer(lines, t)
        when "eu_bank_transfer" then format_eu_bank_transfer(lines, t)
        else
          result.service_failure!(
            code: "unsupported_funding_type",
            message: "Funding type '#{funding_data[:type]}' is not supported"
          )
        end

        result.details = lines.join("\n")
        result
      end
    end

    private

    attr_reader :funding_data, :locale

    def format_us_bank_transfer(lines, t)
      addresses = funding_data[:financial_addresses] || []

      addresses.each do |address|
        type = address[:type]&.to_sym
        details = address[type] || {}

        case type
        when :aba
          lines << "#{t.call(:bank_name)}: #{details_or_default(details[:bank_name])}"
          lines << "#{t.call(:account_number)}: #{details_or_default(details[:account_number])}"
          lines << "#{t.call(:routing_number)}: #{details_or_default(details[:routing_number])}"
          lines << ""
        when :swift
          lines << "#{t.call(:bank_name)}: #{details_or_default(details[:bank_name])}"
          lines << "#{t.call(:account_number)}: #{details_or_default(details[:account_number])}"
          lines << "#{t.call(:swift_code)}: #{details_or_default(details[:swift_code])}"
          lines << ""
        end
      end
    end

    def format_mx_bank_transfer(lines, t)
      details = extract_details(:mx_bank_transfer)
      lines << "#{t.call(:clabe)}: #{details_or_default(details[:clabe])}"
      lines << "#{t.call(:bank_name)}: #{details_or_default(details[:bank_name])}"
      lines << "#{t.call(:bank_code)}: #{details_or_default(details[:bank_code])}"
    end

    def format_jp_bank_transfer(lines, t)
      details = extract_details(:jp_bank_transfer)
      lines << "#{t.call(:bank_code)}: #{details_or_default(details[:bank_code])}"
      lines << "#{t.call(:bank_name)}: #{details_or_default(details[:bank_name])}"
      lines << "#{t.call(:branch_code)}: #{details_or_default(details[:branch_code])}"
      lines << "#{t.call(:branch_name)}: #{details_or_default(details[:branch_name])}"
      lines << "#{t.call(:account_type)}: #{details_or_default(details[:account_type])}"
      lines << "#{t.call(:account_number)}: #{details_or_default(details[:account_number])}"
      lines << "#{t.call(:account_holder_name)}: #{details_or_default(details[:account_holder_name])}"
    end

    def format_gb_bank_transfer(lines, t)
      details = extract_details(:sort_code)
      lines << "#{t.call(:account_number)}: #{details_or_default(details[:account_number])}"
      lines << "#{t.call(:sort_code)}: #{details_or_default(details[:sort_code])}"
      lines << "#{t.call(:account_holder_name)}: #{details_or_default(details[:account_holder_name])}"
    end

    def format_eu_bank_transfer(lines, t)
      details = extract_details(:iban)
      lines << "#{t.call(:bic)}: #{details_or_default(details[:bic])}"
      lines << "#{t.call(:iban)}: #{details_or_default(details[:iban])}"
      lines << "#{t.call(:country)}: #{details_or_default(details[:country])}"
      lines << "#{t.call(:account_holder_name)}: #{details_or_default(details[:account_holder_name])}"
    end

    def extract_details(key)
      funding_data[:financial_addresses]&.first&.dig(key) || {}
    end

    def details_or_default(value)
      value.presence || "-"
    end
  end
end
