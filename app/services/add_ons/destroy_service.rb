# frozen_string_literal: true

module AddOns
  class DestroyService < BaseService
    def destroy(id)
      add_on = result.user.add_ons.find_by(id: id)
      return result.not_found_failure!(code: 'add_on_not_found') unless add_on

      add_on.destroy!

      result.add_on = add_on
      result
    end

    def destroy_from_api(organization:, code:)
      add_on = organization.add_ons.find_by(code: code)
      return result.not_found_failure!(code: 'add_on_not_found') unless add_on

      add_on.destroy!

      result.add_on = add_on
      result
    end
  end
end
