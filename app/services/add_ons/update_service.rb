# frozen_string_literal: true

module AddOns
  class UpdateService < BaseService
    def update(**args)
      add_on = result.user.add_ons.find_by(id: args[:id])
      return result.not_found_failure!(resource: 'add_on') unless add_on

      add_on.name = args[:name]
      add_on.code = args[:code]
      add_on.description = args[:description]
      add_on.amount_cents = args[:amount_cents]
      add_on.amount_currency = args[:amount_currency]

      add_on.save!

      result.add_on = add_on
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def update_from_api(organization:, code:, params:)
      add_on = organization.add_ons.find_by(code: code)
      return result.not_found_failure!(resource: 'add_on') unless add_on

      add_on.name = params[:name] if params.key?(:name)
      add_on.code = params[:code] if params.key?(:code)
      add_on.amount_cents = params[:amount_cents] if params.key?(:amount_cents)
      add_on.amount_currency = params[:amount_currency] if params.key?(:amount_currency)
      add_on.description = params[:description] if params.key?(:description)

      add_on.save!

      result.add_on = add_on
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end
  end
end
