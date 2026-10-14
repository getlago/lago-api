# frozen_string_literal: true

# Postgres rejects strings containing a null byte, which used to surface as a 500 (search terms,
# filters, GraphQL arguments). Like NullByteSanitizable does for some model attributes, null bytes
# are stripped from the request parameters.
#
# The detection runs on the raw request (a single string scan, no parsing or copy), so it adds no
# measurable cost, including on the events endpoints. Parameters are only rewritten for the rare
# request that carries one.
module NullByteGuard
  NULL_BYTE = "\u0000"
  # Percent-encoded in a URL or a form body, escaped in a JSON body.
  ENCODED_NULL_BYTE = "%00"
  JSON_NULL_BYTE = "\\u0000"

  module_function

  def contains_null_byte?(request)
    return true if request.fullpath.include?(ENCODED_NULL_BYTE)
    # File uploads are binary and legitimately contain null bytes.
    return false if request.media_type == "multipart/form-data"

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

  def strip_params!(params)
    params.keys.each { |key| params[key] = strip_param(params[key]) }
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
