# frozen_string_literal: true

FactoryBot.define do
  factory :credit_note_item do
    credit_note
    fee
    amount_cents { 100 }
    precise_amount_cents { 100 }
    amount_currency { "EUR" }
  end
end
