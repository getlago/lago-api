# frozen_string_literal: true

module FilterPrecedence
  # Prefer more keys, then fewer expanded values, then the oldest filter. Unsaved default
  # buckets sort last; the ID breaks ties between filters created at the same time.
  def precedence
    @precedence ||= begin
      allowed_values = to_h_with_all_values
      age = created_at ? [0, created_at, id] : [1]

      [-allowed_values.size, allowed_values.sum { |_key, values| values.size }, age].freeze
    end
  end
end
