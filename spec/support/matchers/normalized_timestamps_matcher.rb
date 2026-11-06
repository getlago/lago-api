# frozen_string_literal: true

# Every string of a payload shaped like a date or a datetime is a UTC datetime to the microsecond
# or a calendar day. Matched on values rather than key names, so that `effective_from` is covered.
# Free text that only starts with a date, such as a name, is left alone.
RSpec::Matchers.define :have_normalized_timestamps do
  date_like = /\A\d{4}-\d{2}-\d{2}(?:\z|[T ]\d)/
  formats = [/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/, /\A\d{4}-\d{2}-\d{2}\z/]

  match do |payload|
    @offenses = {}
    collect_offenses = lambda do |value, path|
      case value
      when Hash
        value.each { |key, child| collect_offenses.call(child, path ? "#{path}.#{key}" : key.to_s) }
      when Array
        value.each_with_index { |child, index| collect_offenses.call(child, "#{path}[#{index}]") }
      when String
        @offenses[path] = value if value.match?(date_like) && formats.none? { value.match?(it) }
      end
    end
    collect_offenses.call(payload, nil)

    @offenses.empty?
  end

  failure_message do
    "expected datetimes as 2026-10-16T10:00:00.123456Z and dates as 2026-10-16, got #{@offenses.inspect}"
  end
end
