# frozen_string_literal: true

module DataExports
  module Csv
    # Writes CSV rows with every value quoted, so a spreadsheet splitting rows on another separator
    # than the comma (Excel uses the locale list separator, often ";") keeps each value in one cell.
    #
    # nil is written as an empty unquoted field, as Ruby's CSV does by default, so tools reading the
    # file (for example `COPY ... CSV` in Postgres) still tell a missing value from an empty string.
    # CSV's force_quotes option would write both as "".
    class QuotedWriter
      def initialize(io)
        @io = io
      end

      def <<(row)
        @io << row.map { |field| format_field(field) }.join(",") << "\n"
        self
      end

      private

      def format_field(field)
        return "" if field.nil?

        %("#{String(FormulaEscaper.escape(field)).gsub('"', '""')}")
      end
    end
  end
end
