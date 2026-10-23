# frozen_string_literal: true

module CursorPagination
  # Opaque cursor: Base64URL of `{"v": version, "o": {"t": table, "s": sort}, "k": key}`,
  # the key holding one value per sort column, in the order of the sort.
  #
  # It is not signed. Every query is scoped to the organization of the API key, so a
  # forged cursor only repositions its caller within their own data. It is validated
  # strictly instead, so that a bad cursor is a 400 and never reaches Postgres.
  module Token
    VERSION = 1
    MAX_LENGTH = 512
    ENCODED_FORMAT = /\A[A-Za-z0-9_-]+\z/
    # PostgreSQL has no year 0, which Ruby parses: a key in that year is malformed rather than
    # a failing query.
    TIMESTAMP_FORMAT = /\A(?!0000)\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/
    DATE_FORMAT = /\A(?!0000)\d{4}-\d{2}-\d{2}\z/

    def self.encode(table:, record:, sort: DEFAULT_SORT)
      CursorPagination.validate_sort!(sort)

      payload = {
        v: VERSION,
        o: {t: table, s: CursorPagination.signature(sort)},
        k: sort.keys.map { |column| written_value(column, record.public_send(column)) }
      }

      Base64.urlsafe_encode64(payload.to_json, padding: false)
    end

    # Returns the key of the anchor row, one typed value per sort column. `param` names
    # the request parameter the value came from, to key the error details.
    def self.decode(value, table:, param:, sort: DEFAULT_SORT)
      CursorPagination.validate_sort!(sort)
      invalid = ->(reason) { raise Error.new(code: Error::INVALID_CURSOR, details: {param => {reason:}}) }

      # A request parameter can also arrive as an array or a hash (`after[]=`, `after[k]=`).
      invalid.call("malformed") unless value.is_a?(String)
      invalid.call("too_long") if value.bytesize > MAX_LENGTH
      invalid.call("malformed") unless value.match?(ENCODED_FORMAT)

      payload = parse(value)
      invalid.call("malformed") unless payload.is_a?(Hash) && payload.keys.sort == %w[k o v]
      invalid.call("unsupported_version") unless payload["v"].eql?(VERSION)

      ordering = payload["o"]
      invalid.call("malformed") unless ordering.is_a?(Hash) && ordering.keys.sort == %w[s t]
      invalid.call("wrong_resource") unless ordering["t"] == table

      if ordering["s"] != CursorPagination.signature(sort)
        raise Error.new(code: Error::CURSOR_EXPIRED, details: {param => {reason: "sort_changed"}})
      end

      key(payload["k"], sort) || invalid.call("malformed_key")
    end

    def self.parse(value)
      JSON.parse(Base64.urlsafe_decode64(value))
    rescue ArgumentError, EncodingError, JSON::ParserError
      nil
    end
    private_class_method :parse

    def self.key(values, sort)
      return unless values.is_a?(Array) && values.size == sort.size

      key = sort.keys.zip(values).map { |column, value| read_value(column, value) }
      key unless key.include?(nil)
    rescue ArgumentError
      # A well-shaped but impossible date or timestamp, like month 13.
      nil
    end
    private_class_method :key

    def self.written_value(column, value)
      case column
      when :issuing_date then value.iso8601
      when :created_at then value.utc.iso8601(6)
      when :id then value
      end
    end
    private_class_method :written_value

    # Read back as the type the column compares with: a date stays a `Date`, so that a
    # timestamp is never resumed in its place. Nil when the value is not of that format.
    def self.read_value(column, value)
      return unless value.is_a?(String)

      case column
      when :issuing_date then Date.iso8601(value) if value.match?(DATE_FORMAT)
      when :created_at then Time.iso8601(value) if value.match?(TIMESTAMP_FORMAT)
      when :id then value if value.match?(BaseQuery::UUID_REGEX)
      end
    end
    private_class_method :read_value
  end
end
