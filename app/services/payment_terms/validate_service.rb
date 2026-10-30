# frozen_string_literal: true

module PaymentTerms
  class ValidateService < BaseValidator
    DAYS_RANGE = (0..365)
    DAY_OF_MONTH_RANGE = (1..31)
    MONTH_OFFSET_RANGE = (0..12)

    def valid?
      valid_net_payment_term?
      valid_payment_term?

      if errors?
        result.validation_failure!(errors:)
        return false
      end

      true
    end

    private

    def valid_net_payment_term?
      value = args[:net_payment_term]
      if value.nil?
        true
      elsif !value.is_a?(Integer)
        add_error(field: :net_payment_term, error_code: "invalid_format")
      elsif value.negative?
        add_error(field: :net_payment_term, error_code: "value_is_out_of_range")
      else
        true
      end
    end

    def valid_payment_term?
      return true if payment_term.nil?

      if !payment_term.is_a?(Hash)
        return add_error(field: :payment_term, error_code: "invalid_format")
      end

      unless PaymentTerm::FIELDS_BY_TERM_TYPE.key?(term_type)
        return add_error(field: :payment_term, error_code: "invalid_term_type")
      end

      valid_fields?
      valid_days?
      valid_day_of_month?
      valid_month_offset?
    end

    def payment_term
      args[:payment_term]
    end

    def term_type
      payment_term[:term_type]
    end

    def term_fields
      PaymentTerm::FIELDS_BY_TERM_TYPE.fetch(term_type)
    end

    def valid_fields?
      unexpected = payment_term.keys.map(&:to_s) - ["term_type"] - term_fields
      return true if unexpected.empty?

      add_error(field: :payment_term, error_code: "unexpected_fields")
    end

    def valid_days?
      return true unless term_fields.include?("days")

      days = payment_term[:days]

      return true if days.is_a?(Integer) && DAYS_RANGE.cover?(days)

      add_error(field: :payment_term, error_code: "invalid_days")
    end

    def valid_day_of_month?
      return true unless term_fields.include?("day_of_month")

      day = payment_term[:day_of_month]
      return true if day.is_a?(Integer) && DAY_OF_MONTH_RANGE.cover?(day)

      add_error(field: :payment_term, error_code: "invalid_day_of_month")
    end

    def valid_month_offset?
      return true unless term_fields.include?("month_offset")

      offset = payment_term[:month_offset]
      # Absent is fine: PaymentTerm.from_h fills the default (1).
      return true if offset.nil?
      return true if offset.is_a?(Integer) && MONTH_OFFSET_RANGE.cover?(offset)

      add_error(field: :payment_term, error_code: "invalid_month_offset")
    end
  end
end
