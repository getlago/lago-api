# frozen_string_literal: true

class ValidateApiKeysMembershipForeignKey < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :api_keys, :memberships
  end
end
