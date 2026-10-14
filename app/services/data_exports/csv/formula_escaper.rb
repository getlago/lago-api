# frozen_string_literal: true

module DataExports
  module Csv
    # Spreadsheets (Excel, Google Sheets, LibreOffice) evaluate a cell as a formula when its text starts
    # with a formula character. Exported values can come from end customers (names, emails, tax IDs set
    # through the customer portal), so text values that would be read as a formula get a leading
    # apostrophe, which makes the spreadsheet show them as plain text.
    module FormulaEscaper
      FORMULA_CHARACTERS = "=+\\-@＝＋－＠"

      # A formula character first, possibly after whitespace or control characters, or a leading
      # tab, CR or LF on their own.
      FORMULA_PATTERN = /\A(?:[\t\r\n]|[\p{Space}\p{Cc}]*[#{FORMULA_CHARACTERS}])/

      # Plain numbers such as "-150" or "-1.5" are left as is so they stay numbers in the spreadsheet.
      NUMBER_PATTERN = /\A[+-]?\d+(?:\.\d+)?\z/

      CONVERTER = ->(field) { escape(field) }

      module_function

      def escape(value)
        return value unless value.is_a?(String)
        return value if NUMBER_PATTERN.match?(value)
        return value unless FORMULA_PATTERN.match?(value)

        "'#{value}"
      end
    end
  end
end
