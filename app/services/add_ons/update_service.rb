# frozen_string_literal: true

module AddOns
  class UpdateService < BaseService
    def update(**args)
      add_on = result.user.add_ons.find_by(id: args[:id])
      return result.fail!('not_found') unless add_on

      add_on.name = args[:name]
      add_on.code = args[:code]
      add_on.description = args[:description]
      add_on.amount_cents = args[:amount_cents]
      add_on.amount_currency = args[:amount_currency]

      add_on.save!

      result.add_on = add_on
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end
  end
end
