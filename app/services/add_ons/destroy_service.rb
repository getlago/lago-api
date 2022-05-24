# frozen_string_literal: true

module AddOns
  class DestroyService < BaseService
    def destroy(id)
      add_on = result.user.add_ons.find_by(id: id)
      return result.fail!('not_found') unless add_on

      add_on.destroy!

      result.add_on = add_on
      result
    end
  end
end
