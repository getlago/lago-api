# frozen_string_literal: true

class AddRequestKeyDigestToX402Settlements < ActiveRecord::Migration[8.1]
  def change
    add_column :x402_settlements, :request_key_digest, :string, if_not_exists: true

    add_check_constraint :x402_settlements,
      "request_key_digest IS NULL OR request_key_digest ~ '^[0-9a-f]{64}$'",
      name: "check_x402_settlements_request_key_digest_format",
      validate: false,
      if_not_exists: true
    add_check_constraint :x402_settlements,
      "kind <> 'invoice_payment' OR request_key_digest IS NULL",
      name: "check_x402_settlements_invoice_payment_has_no_request_key",
      validate: false,
      if_not_exists: true
  end
end
