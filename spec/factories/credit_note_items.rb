# frozen_string_literal: true

FactoryBot.define do
  factory :credit_note_item do
    credit_note
    fee { association(:fee, organization:, invoice: credit_note.invoice) }
    organization { credit_note.organization }
    amount_cents { 100 }
    precise_amount_cents { 100 }
    amount_currency { "EUR" }
  end
end
