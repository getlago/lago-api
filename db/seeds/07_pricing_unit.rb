# frozen_string_literal: true

hooli = Organization.find_by!(name: "Hooli")

unless PricingUnit.exists?(code: "xyz")
  PricingUnits::CreateService.call!(
    organization: hooli,
    name: "xyz",
    code: "xyz",
    short_name: "XYZ"
  )
end
