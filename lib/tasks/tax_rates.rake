# frozen_string_literal: true

namespace :tax_rates do
  desc 'Migrate vat_rate to tax rates for organizations and customers'
  task migrate_from_vate_rate: :environment do
    ::Organization.where('vat_rate > 0').find_each do |organization|
      organization.tax_rates.create_with(
        value: organization.vat_rate,
        name: "Tax (#{organization.vat_rate}%)",
        applied_by_default: true,
      ).find_or_create_by!(code: "tax_#{organization.vat_rate}")
    end

    ::Customer.where.not(vat_rate: nil).find_each do |customer|
      tax_rate = ::TaxRate.create_with(
        name: "Tax (#{customer.vat_rate}%)",
        value: customer.vat_rate,
      ).find_or_create_by!(
        organization_id: customer.organization_id,
        code: "tax_#{customer.vat_rate}",
      )

      customer.applied_tax_rates.create!(tax_rate:)
    end
  end
end
