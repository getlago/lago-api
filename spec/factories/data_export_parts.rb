# frozen_string_literal: true

FactoryBot.define do
  factory :data_export_part do
    data_export

    index { 0 }
    object_ids { [] }
  end
end
