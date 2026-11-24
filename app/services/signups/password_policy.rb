# frozen_string_literal: true

module Signups
  module PasswordPolicy
    MIN_LENGTH = 8

    module_function

    # Every rule the password fails, in the order the front shows them. bcrypt ignores what follows 72 bytes.
    def violations(password)
      password = password.to_s.scrub

      [
        ("password_too_short" if password.length < MIN_LENGTH),
        ("password_missing_lowercase" unless password.match?(/\p{Ll}/)),
        ("password_missing_uppercase" unless password.match?(/\p{Lu}/)),
        ("password_missing_number" unless password.match?(/\p{Nd}/)),
        ("password_missing_special_character" unless password.match?(/[^\p{L}\p{N}\s]/)),
        ("password_too_long" if password.bytesize > ActiveModel::SecurePassword::MAX_PASSWORD_LENGTH_ALLOWED)
      ].compact
    end
  end
end
