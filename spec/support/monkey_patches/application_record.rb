# frozen_string_literal: true

# In test env, :direct and :writing point at the same DB but Rails opens
# distinct pools — separate PG sessions, and DatabaseCleaner only wraps
# the default pool. Short-circuit the role swap so :direct queries land
# on the currently-active pool and see fixtures written via :writing.
class ApplicationRecord < ActiveRecord::Base
  def self.connected_to(role: nil, **kwargs)
    return yield if role == :direct
    super
  end
end
