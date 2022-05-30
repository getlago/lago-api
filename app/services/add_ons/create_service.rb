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
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end
  end
end
