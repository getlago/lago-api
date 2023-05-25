# frozen_string_literal: true

namespace :taxes do
  desc 'Migrate vat_rate to tax rates for organizations and customers'
  task migrate_from_vate_rate: :environment do
    ::Organization.where('vat_rate > 0').find_each do |organization|
      organization.taxes.create_with(
        rate: organization.vat_rate,
        name: "Tax (#{organization.vat_rate}%)",
        applied_to_organization: true,
      ).find_or_create_by!(code: "tax_#{organization.vat_rate}")
    end

    ::Customer.where.not(vat_rate: nil).find_each do |customer|
      tax = ::Tax.create_with(
        name: "Tax (#{customer.vat_rate}%)",
        rate: customer.vat_rate,
      ).find_or_create_by!(
        organization_id: customer.organization_id,
        code: "tax_#{customer.vat_rate}",
      )

      customer.applied_taxes.create!(tax:)
    end
  end
end
