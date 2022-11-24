# frozen_string_literal: true

module Types
  class TimezoneEnum < Types::BaseEnum
    ActiveSupport::TimeZone.all
      .uniq { |tz| tz.tzinfo.identifier }
      .each_with_object([]) { |tz, result| result << [tz.tzinfo.identifier.gsub('Etc/', ''), tz] }
      .sort_by { |list| list.first.split('/') }
      .map do |list|
        symbol = list.first.gsub(/[^_a-zA-Z0-9]/, '_').squeeze('_').upcase
        value("TZ_#{symbol}", list.first, value: list.first)
      end
  end
end
