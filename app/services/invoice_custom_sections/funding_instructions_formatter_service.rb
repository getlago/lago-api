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
        when "us_bank_transfer"
          format_us_bank_transfer(lines, t)
        when "mx_bank_transfer"
          format_mx_bank_transfer(lines, t)
        when "jp_bank_transfer"
          format_jp_bank_transfer(lines, t)
        when "gb_bank_transfer"
          format_gb_bank_transfer(lines, t)
        when "eu_bank_transfer"
          format_eu_bank_transfer(lines, t)
        else
          lines << "- #{t.call(:bank_transfer_info)} -"
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
    end

    def format_mx_bank_transfer(lines, t)
      details = funding_data.dig(:financial_addresses, 0, :mx_bank_transfer) || {}
      lines << "#{t.call(:clabe)} #{details[:clabe] || "-"}"
      lines << "#{t.call(:bank_name)} #{details[:bank_name] || "-"}"
      lines << "#{t.call(:bank_code)} #{details[:bank_code] || "-"}"
    end

    def format_jp_bank_transfer(lines, t)
      details = funding_data.dig(:financial_addresses, 0, :jp_bank_transfer) || {}
      lines << "#{t.call(:bank_code)} #{details[:bank_code] || "-"}"
      lines << "#{t.call(:bank_name)} #{details[:bank_name] || "-"}"
      lines << "#{t.call(:branch_code)} #{details[:branch_code] || "-"}"
      lines << "#{t.call(:branch_name)} #{details[:branch_name] || "-"}"
      lines << "#{t.call(:account_type)} #{details[:account_type] || "-"}"
      lines << "#{t.call(:account_number)} #{details[:account_number] || "-"}"
      lines << "#{t.call(:account_holder_name)} #{details[:account_holder_name] || "-"}"
    end

    def format_gb_bank_transfer(lines, t)
      details = funding_data.dig(:financial_addresses, 0, :sort_code) || {}
      lines << "#{t.call(:account_number)} #{details[:account_number] || "-"}"
      lines << "#{t.call(:sort_code)} #{details[:sort_code] || "-"}"
      lines << "#{t.call(:account_holder_name)} #{details[:account_holder_name] || "-"}"
    end

    def format_eu_bank_transfer(lines, t)
      details = funding_data.dig(:financial_addresses, 0, :iban) || {}
      lines << "#{t.call(:bic)} #{details[:bic] || "-"}"
      lines << "#{t.call(:iban)} #{details[:iban] || "-"}"
      lines << "#{t.call(:country)} #{details[:country] || "-"}"
      lines << "#{t.call(:account_holder_name)} #{details[:account_holder_name] || "-"}"
    end
  end
end
