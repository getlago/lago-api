# frozen_string_literal: true

class Invoice < ApplicationRecord; end

class MigrateIssuerAndRecipientFromInvoices < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    Invoice.update_all( # rubocop:disable Rails/SkipsModelValidations
      "issuer_id = organization_id, issuer_type = 'Organization', " \
      "recipient_id = customer_id, recipient_type = 'Customer'"
    )
  end
end
