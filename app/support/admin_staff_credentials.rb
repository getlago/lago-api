# frozen_string_literal: true

# ⚠️  HACKATHON ONLY ⚠️
# Plain-text credentials for the internal premium-toggle admin tool.
# Do NOT use this pattern for anything that survives the demo.
# Passwords here are checked at login by Mutations::Admin::LoginUser.
# Role controls which integrations the user can toggle — see
# Admin::PremiumIntegrations::ToggleService::ROLE_ALLOWED_INTEGRATIONS.

module AdminStaffCredentials
  # email => [password, role]
  ENTRIES = {
    "miguel@getlago.com" => ["8Kx3pL9qR2nZvWm5Yf7T", :admin],
    "at@getlago.com"     => ["bN4jH7gD2sFw9RkT3Mq6", :admin],
    "anh-tu@getlago.com" => ["Vx5eC8nP1rLhU7kG3JwZ", :admin],
    "brian@getlago.com"  => ["q2HbR9tXmW4yK6LdVs8E", :admin],
    "raffi@getlago.com"  => ["F7zP3nQmT5vC8kLrW2Bd", :admin],
    "jeremy@getlago.com" => ["g4MhJ6xVnR9TkL3wE8Cp", :admin],
    "lovro@getlago.com"  => ["K2rT7mBnW4xV6qL9cPf3", :cs]
  }.freeze

  StaffUser = Struct.new(:email, :role, keyword_init: true) do
    def id
      email
    end
  end

  def self.authenticate(email, password)
    normalized = email.to_s.downcase.strip
    entry = ENTRIES[normalized]
    return nil if entry.nil?

    expected_password, role = entry
    return nil unless ActiveSupport::SecurityUtils.secure_compare(password.to_s, expected_password)

    StaffUser.new(email: normalized, role: role)
  end

  def self.find(email)
    normalized = email.to_s.downcase.strip
    entry = ENTRIES[normalized]
    return nil if entry.nil?

    _password, role = entry
    StaffUser.new(email: normalized, role: role)
  end

  def self.exists?(email)
    ENTRIES.key?(email.to_s.downcase.strip)
  end
end
