# frozen_string_literal: true

FactoryBot.define do
  factory :catalog_reference, class: "OrderForm::CatalogReference" do
    order_form
    organization
    referenced_type { "subscription" }
    referenced_id { "1234-5678" }
  end
end
