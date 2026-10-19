# frozen_string_literal: true

# Postgres rejects strings containing a null byte, which used to surface as a 500 (search terms,
# filters, GraphQL arguments). Like NullByteSanitizable does for some model attributes, null bytes
# are stripped from the request parameters.
#
# The detection runs on the raw request (a single string scan, no parsing or copy), so it adds no
# measurable cost, including on the events endpoints. Parameters are only rewritten for the rare
# request that carries one, or for a multipart request (see strip_needed?).
module NullByteGuard
  NULL_BYTE = "\u0000"
  # Percent-encoded in a URL or a form body, escaped in a JSON body.
  ENCODED_NULL_BYTE = "%00"
  JSON_NULL_BYTE = "\\u0000"

  module_function

  # Entry points for controllers: clean the parameters only when the request may carry a null byte.
  def sanitize_params!(request, params)
    strip_params!(params) if strip_needed?(request)
    params
  end

  def sanitize(request, value)
    strip_needed?(request) ? strip(value) : value
  end

  # A multipart body holds binary uploads that legitimately contain null bytes, so it can't be
  # scanned. Its text fields are cleaned instead; uploaded files are not strings and stay untouched.
  def strip_needed?(request)
    request.media_type == "multipart/form-data" || contains_null_byte?(request)
  end

  def contains_null_byte?(request)
    return true if request.fullpath.include?(ENCODED_NULL_BYTE)

    body = request.raw_post
    return false if body.blank?

    body.include?(JSON_NULL_BYTE) || body.include?(ENCODED_NULL_BYTE) || body.include?(NULL_BYTE)
  end

  def strip(value)
    case value
    when String then value.delete(NULL_BYTE)
    when Hash then value.to_h { |k, v| [strip(k), strip(v)] }
    when Array then value.map { strip(it) }
    else value
    end
  end

  # Keys are cleaned too: a null byte in a JSON object key (event properties, metadata) is
  # rejected by Postgres as well.
  def strip_params!(params)
    params.keys.each do |key|
      value = strip_param(params[key])
      clean_key = key.to_s.delete(NULL_BYTE)

      params.delete(key) unless clean_key == key.to_s
      params[clean_key] = value
    end

    params
  end

  def strip_param(value)
    case value
    when String then value.delete(NULL_BYTE)
    when ActionController::Parameters then strip_params!(value)
    when Array then value.map { strip_param(it) }
    else value
    end
  end
end
