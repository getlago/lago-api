# frozen_string_literal: true

class ValidateX402SettlementsRequestKeyDigest < ActiveRecord::Migration[8.1]
  def change
    validate_check_constraint :x402_settlements, name: "check_x402_settlements_request_key_digest_format"
    validate_check_constraint :x402_settlements, name: "check_x402_settlements_invoice_payment_has_no_request_key"
  end
end
