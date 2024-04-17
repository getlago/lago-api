# frozen_string_literal: true

class Hash
  def to_dotted_hash(recursive_key: '', separator: '.')
    each_with_object({}) do |(k, v), ret|
      key = recursive_key + k.to_s
      if v.is_a?(Hash)
        ret.merge!(v.to_dotted_hash(recursive_key: key + separator, separator:))
      else
        ret[key] = v
      end
    end
  end
end
