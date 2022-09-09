# frozen_string_literal: true

module Plans
  class DestroyService < BaseService
    def destroy(id)
      plan = result.user.plans.find_by(id: id)
      return result.not_found_failure!(resource: 'plan') unless plan
      return result.not_allowed_failure!(code: 'attached_to_an_active_subscription') unless plan.deletable?

      plan.destroy!

      result.plan = plan
      result
    end

    def destroy_from_api(organization:, code:)
      plan = organization.plans.find_by(code: code)
      return result.not_found_failure!(resource: 'plan') unless plan
      return result.not_allowed_failure!(code: 'attached_to_an_active_subscription') unless plan.deletable?

      plan.destroy!

      result.plan = plan
      result
    end
  end
end
