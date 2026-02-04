# frozen_string_literal: true

if Rails.env.development? || ENV["FORCE_PREMIUM"] == "true"
  License.instance_variable_set(:@premium, true)
end