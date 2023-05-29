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

  desc 'Create fees_taxes for existing fees'
  task create_fees_taxes: :environment do
    sub_query = Fee.where('taxes_rate > 0').left_joins(:fees_taxes)
      .group('fees.id')
      .having('COUNT(fees_taxes.id) = 0')
      .select(:id)

    Fee.where(id: sub_query).each do |fee|
      organization = fee.organization || fee.subscription&.customer&.organization

      tax = ::Tax.create_with(
        name: "Tax (#{fee.taxes_rate})",
        rate: fee.taxes_rate,
      ).find_or_create_by!(
        organization_id: organization.id,
        code: "tax_#{fee.taxes_rate}",
      )

      FeesTax.create!(
        fee:,
        tax:,
        tax_description: tax.description,
        tax_code: tax.code,
        tax_name: tax.name,
        tax_rate: tax.rate,
        amount_currency: fee.currency,
        amount_cents: fee.taxes_amount_cents,
      )
    end
  end
end
