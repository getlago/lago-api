# frozen_string_literal: true

FactoryBot.define do
  factory :presentation_breakdown do
    organization { fee&.organization || association(:organization) }
    fee factory: :charge_fee

    breakdowns do
      [
        {presentation_by: {department: "engineering"}, units: "60.0"},
        {presentation_by: {department: "sales"}, units: "40.0"}
      ]
    end
  end
end
