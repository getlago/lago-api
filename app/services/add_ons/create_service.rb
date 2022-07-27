# frozen_string_literal: true

module AddOns
  class CreateService < BaseService
    def create(**args)
      add_on = AddOn.create!(
        organization_id: args[:organization_id],
        name: args[:name],
        code: args[:code],
        description: args[:description],
        amount_cents: args[:amount_cents],
        amount_currency: args[:amount_currency],
      )

      result.add_on = add_on
      track_add_on_create(result.add_on)
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    def track_add_on_create(add_on)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: 'add_on_create',
        properties: {
          addon_code: add_on.code,
          addon_name: add_on.name,
          organization_id: add_on.organization_id
        }
      )
    end
  end
end
