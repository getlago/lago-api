# frozen_string_literal: true

module PaymentTerms
  class ValidateService < BaseValidator
    # Discriminated union: each term_type carries only its own fields.
    FIELDS_BY_TERM_TYPE = {
      "due_on_receipt" => [],
      "net" => %w[days],
      "end_of_month" => [],
      "net_end_of_month" => %w[days],
      "days_end_of_month" => %w[days],
      "day_of_month" => %w[day_of_month month_offset]
    }.freeze

    MAX_DAYS = 365
    DAY_OF_MONTH_RANGE = (1..31)
    MONTH_OFFSET_RANGE = (0..12)

    def valid?
      if payment_term.nil?
        return true
      end

      if !payment_term.is_a?(Hash)
        add_error(field: :payment_term, error_code: "invalid_format")
      elsif !FIELDS_BY_TERM_TYPE.key?(term_type)
        add_error(field: :payment_term, error_code: "invalid_term_type")
      else
        valid_fields?
        valid_days?
        valid_day_of_month?
        valid_month_offset?
      end

      if errors?
        result.validation_failure!(errors:)
        return false
      end

      true
    end

    private

    def payment_term
      args[:payment_term]
    end

    def term_type
      payment_term[:term_type]
    end

    def valid_fields?
      unexpected = payment_term.keys.map(&:to_s) - ["term_type"] - FIELDS_BY_TERM_TYPE.fetch(term_type)
      return true if unexpected.empty?

      add_error(field: :payment_term, error_code: "unexpected_fields")
    end

    def valid_days?
      return true unless FIELDS_BY_TERM_TYPE.fetch(term_type).include?("days")

      days = payment_term[:days]
      return true if days.is_a?(Integer) && days >= 0 && days <= MAX_DAYS

      add_error(field: :payment_term, error_code: "invalid_days")
    end

    def valid_day_of_month?
      return true unless term_type == "day_of_month"

      day = payment_term[:day_of_month]
      return true if day.is_a?(Integer) && DAY_OF_MONTH_RANGE.cover?(day)

      add_error(field: :payment_term, error_code: "invalid_day_of_month")
    end

    def valid_month_offset?
      return true unless term_type == "day_of_month"

      offset = payment_term[:month_offset]
      # Absent is fine: PaymentTerm.from_h fills the default (1).
      return true if offset.nil?
      return true if offset.is_a?(Integer) && MONTH_OFFSET_RANGE.cover?(offset)

      add_error(field: :payment_term, error_code: "invalid_month_offset")
    end
  end
end
