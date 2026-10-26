# frozen_string_literal: true

module CursorPagination
  # Opaque cursor: Base64URL of `{"v": version, "o": {"t": table, "s": sort}, "k": [time, tiebreak]}`,
  # where `time` is the ISO8601 value of the sort's first column and `tiebreak` the string
  # value of its second (a UUID `id` on the Postgres lists, a string business id on the logs).
  #
  # It is not signed. Every query is scoped to the organization of the API key, so a
  # forged cursor only repositions its caller within their own data. It is validated
  # strictly instead, so that a bad cursor is a 400 and never reaches Postgres.
  module Token
    VERSION = 1
    MAX_LENGTH = 512
    # Upper bound of the tiebreak value carried in a key: a UUID id or a short business id
    # fit well under it, and the whole token is already capped at `MAX_LENGTH`.
    MAX_KEY_LENGTH = 256
    ENCODED_FORMAT = /\A[A-Za-z0-9_-]+\z/
    TIMESTAMP_FORMAT = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/

    def self.encode(table:, record:, sort: DEFAULT_SORT)
      CursorPagination.validate_sort!(sort)

      time_column, tiebreak_column = sort.keys
      payload = {
        v: VERSION,
        o: {t: table, s: CursorPagination.signature(sort)},
        k: [record.public_send(time_column).utc.iso8601(6), record.public_send(tiebreak_column).to_s]
      }

      Base64.urlsafe_encode64(payload.to_json, padding: false)
    end

    # Returns the `[time, tiebreak]` key of the anchor row. `param` names the request
    # parameter the value came from, to key the error details.
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

      key(payload["k"]) || invalid.call("malformed_key")
    end

    def self.parse(value)
      JSON.parse(Base64.urlsafe_decode64(value))
    rescue ArgumentError, EncodingError, JSON::ParserError
      nil
    end
    private_class_method :parse

    def self.key(values)
      return unless values.is_a?(Array) && values.size == 2

      timestamp, tiebreak = values
      if timestamp.is_a?(String) && timestamp.match?(TIMESTAMP_FORMAT) && valid_tiebreak?(tiebreak)
        [Time.iso8601(timestamp), tiebreak]
      end
    rescue ArgumentError
      # A well-shaped but impossible timestamp, like month 13.
      nil
    end
    private_class_method :key

    # The tiebreak is any opaque key the sort's second column holds: a UUID id or a string
    # business id. It is only required to be a bounded, non-empty string, so a non-string,
    # empty, or over-long value is rejected before the cursor reaches the database.
    def self.valid_tiebreak?(value)
      value.is_a?(String) && !value.empty? && value.bytesize <= MAX_KEY_LENGTH
    end
    private_class_method :valid_tiebreak?
  end
end
