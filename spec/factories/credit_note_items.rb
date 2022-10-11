# frozen_string_literal: true

FactoryBot.define do
  factory :credit_note_item do
    credit_note
    fee
    credit_amount_cents { 100 }
    credit_amount_currency { 'EUR' }
  end
end
