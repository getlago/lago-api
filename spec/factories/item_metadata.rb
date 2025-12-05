# frozen_string_literal: true

FactoryBot.define do
  factory :item_metadata, class: "Metadata::ItemMetadata" do
    organization
    value { {"key" => "value"} }
  end
end
