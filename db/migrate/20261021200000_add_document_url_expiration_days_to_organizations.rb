# frozen_string_literal: true

class AddDocumentUrlExpirationDaysToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :document_url_expiration_days, :integer, default: 30, null: false, if_not_exists: true
  end
end
