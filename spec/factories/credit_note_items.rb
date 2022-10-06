# frozen_string_literal: true

FactoryBot.define do
  factory :credit_note_item do
    credit_note
    fee
  end
end
