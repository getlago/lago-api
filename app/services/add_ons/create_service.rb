# frozen_string_literal: true

module AddOns
  class CreateService < BaseService
    def create(**args)
      ActiveRecord::Base.transaction do
        add_on = AddOn.create!(
          organization_id: args[:organization_id],
          name: args[:name],
          invoice_display_name: args[:invoice_display_name],
          code: args[:code],
          description: args[:description],
          amount_cents: args[:amount_cents],
          amount_currency: args[:amount_currency],
        )

        if args[:tax_codes]
          taxes_result = AddOns::ApplyTaxesService.call(add_on:, tax_codes: args[:tax_codes])
          return taxes_result unless taxes_result.success?
        end

        result.add_on = add_on
      end

      track_add_on_created(result.add_on)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def track_add_on_created(add_on)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'add_on_created',
        properties: {
          addon_code: add_on.code,
          addon_name: add_on.name,
          addon_invoice_display_name: add_on.invoice_display_name,
          organization_id: add_on.organization_id
        },
      )
    end
  end
end
