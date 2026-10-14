# frozen_string_literal: true

require "csv"
require "forwardable"

module DataExports
  module Csv
    class BaseCsvService < ::BaseService
      Result = BaseResult[:csv_file]

      extend Forwardable

      def call
        result.csv_file = with_csv do |csv|
          collection.each do |item|
            serialize_item(item, csv)
          end
        end

        result
      end

      private

      def with_csv
        tempfile = Tempfile.create([data_export_part.id, ".csv"])
        yield CSV.new(
          tempfile,
          headers: false,
          # Quoting every field keeps each value in one cell when a spreadsheet splits rows on another
          # separator than the comma (Excel uses the locale list separator, often ";").
          force_quotes: true,
          write_converters: [FormulaEscaper::CONVERTER]
        )

        tempfile.rewind
        tempfile
      end
    end
  end
end
